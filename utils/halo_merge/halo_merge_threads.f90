!! This is the cubepm halo catalog merging routine.
!! Accumulates distributed distributed halo catalogs into monolithic file 
!! compile with: mpif77 indexedsort.f90 halo_merge.f90 -o halo_merge

implicit none
include 'mpif.h'
include '../../parameters'

character(len=*),parameter :: halofinds =cubepm_root//'input/halofinds' 

integer, parameter :: nn=nodes_dim**3 !! number of nodes total
integer, parameter :: max_input=100 !! maximum number of catalogs to merge 
integer, parameter :: max_halos=128**3 !!maximum number of halos / catalog

real(4), dimension(6,max_halos) :: halo_in,halo_out   
integer(4), dimension(max_halos) :: isorthalo
real(4), dimension(max_halos) :: mass

character(len=80) ofile 
character(len=5) rank_s
character(len=3) t_s
character(len=7) z_s
integer i,j,k,m
real x,y,z,z_write

integer(4) :: thread,nn_returned, ierr,rank, num_halofinds,fstat,cur_halofind
real(4), dimension(max_input) :: z_halofind

integer(4) :: nh_local,nh_sum
integer(4) :: nodes_returned,tag
real(4) :: nh_total

integer(4), dimension(0:nn-1) :: nh_found
integer(4), dimension(mpi_status_size) :: status

common / rarr / halo_in,halo_out,mass
common / iarr / isorthalo

!! Initialize MPI
 
call mpi_init(ierr)
if (ierr /= mpi_success) call mpi_abort(mpi_comm_world,ierr,ierr)

call mpi_comm_size(mpi_comm_world,nodes_returned,ierr)
if (ierr /= mpi_success) call mpi_abort(mpi_comm_world,ierr,ierr)
if (nodes_returned /= nn ) then
  write(*,*) 'halo_merge compiled for a different number of nodes'
  write(*,*) 'mpirun nodes=',nodes_returned,'halo_merge nodes=',nn
  call mpi_abort(mpi_comm_world,ierr,ierr)
endif
call mpi_comm_rank(mpi_comm_world,rank,ierr)
if (ierr /= mpi_success) call mpi_abort(mpi_comm_world,ierr,ierr)

!! Read in halofinds to recompose

if (rank == 0) then
  open(11,file=halofinds,status='old',iostat=fstat)
  if (fstat /= 0) then
    write(*,*) 'error opening halofind list file'
    write(*,*) 'rank',rank,'file:',halofinds
    call mpi_abort(mpi_comm_world,ierr,ierr)
  endif
  do num_halofinds=1,max_input
    read(unit=11,err=51,end=41,fmt='(f20.10)') z_halofind(num_halofinds)
  enddo
41  num_halofinds=num_halofinds-1
51  close(11)
  write(*,*) 'halofinds to recompose:'
  do i=1,num_halofinds
    write(*,'(f5.1)') z_halofind(i)
  enddo
endif

call mpi_bcast(num_halofinds,1,mpi_integer,0,mpi_comm_world,ierr)

do cur_halofind=1,num_halofinds

!! Read in halos 
  nh_local=0
  nh_found=0
  nh_sum=0  

  if (rank == 0) then
    z_write = z_halofind(cur_halofind)
    write(*,*) 'processing z=',z_write
  endif

  call mpi_bcast(z_write,1,mpi_real,0,mpi_comm_world,ierr)

  write(z_s,'(f7.3)') z_write
  z_s=adjustl(z_s)

  write(rank_s,'(i5)') rank
  rank_s=adjustl(rank_s)

  do thread=1,1 !nt -- currently only 1 thread used for halos!!

    write(t_s,'(i3)') thread
    t_s=adjustl(t_s)

    ofile=output_path//z_s(1:len_trim(z_s))//'halo'//t_s(1:len_trim(t_s))// &
  	  '-'//rank_s(1:len_trim(rank_s))//'.dat'
    open(unit=21,file=ofile,status='old',iostat=fstat,form='formatted')

    if (fstat /= 0) then
      write(*,*) 'error opening catalog'
      write(*,*) 'rank',rank,'file:',ofile
      call mpi_abort(mpi_comm_world,ierr,ierr)
    endif
   
    k=0
    do
      read(21,end=112,fmt='(6f20.10)') halo_in(:,k+1) 
      k=k+1
    enddo 
112 close(21)
    if (k >= max_halos) then
      write(*,*) 'too many halos to read in'
      call mpi_abort(mpi_comm_world,ierr,ierr)
    endif
    nh_local=nh_local+k
    halo_out(:,nh_local-k+1:nh_local)=halo_in(:,:k)
  enddo
  call mpi_gather(nh_local,1,mpi_integer,nh_found,1,mpi_integer,0, &
                  mpi_comm_world,ierr)
  if (rank == 0) then
    do j=0,nn-1
      write(*,*) 'rank:',j,'number of halos=',nh_found(j)
    enddo
    nh_sum=sum(nh_found)
    write(*,*) 'total halos=',nh_sum
    if (nh_sum > max_halos) then
      print *,'too many halos to store'
      call mpi_abort(mpi_comm_world,ierr,ierr)
    endif
  endif

  do j=1,NN-1
    tag=j
    if (rank == 0) then
      call mpi_recv(halo_out(1,nh_local+1),6*nh_found(j),mpi_real, &
                    j,tag,mpi_comm_world,status,ierr)
    elseif (rank == j) then
      call mpi_send(halo_out,6*nh_local,mpi_real,0,tag,mpi_comm_world,ierr)
    endif
    call mpi_barrier(mpi_comm_world,ierr)
    if (rank ==0) nh_local=nh_local+nh_found(j)
  enddo

  if (rank == 0) then
    print *,'finished pass'
    mass(:nh_sum)=halo_out(4,:nh_sum)
    isorthalo(:nh_sum)=(/ (k,k=1,nh_sum) /)
    call indexedsort(nh_sum,mass,isorthalo)
    halo_out(:,:nh_sum)=halo_out(:,isorthalo(:nh_sum))
    ofile=output_path//z_s(1:len_trim(z_s))//'halo.dat'
    open(unit=31,file=ofile,status='replace',iostat=fstat,form='formatted')
    if (fstat /= 0) then
      write(*,*) 'error opening output catalog'
      write(*,*) 'rank',rank,'file:',ofile
      call mpi_abort(mpi_comm_world,ierr,ierr)
    endif
    do j=nh_sum,1,-1
      write(31,'(6f20.10)') halo_out(:,j)
    enddo
    close(31)
  endif

enddo

end 
