!! this routine reports force accuracy for all particles at once!
  subroutine report_force
    implicit none

    include 'mpif.h'
    include 'cubepm.fh'

    real(4), dimension(6,2) :: pair 
    integer(4), dimension(mpi_status_size) :: status
    integer(4) :: i,j
    real(4) :: r(3),acc(3),v(3),F(3),magr,magF,del_F,frac_err
    real(4) :: F_sim(3),magF_sim,magF_sim_r,magF_sim_t
    !integer(4) np_local_store
    !real(4) :: xv_store(6,2)
    real(4) :: x_hole(3), pp_hole
    real(4), dimension(3,max_np):: dv


    if (rank==0) then
       
       !do i=1,20
       !   write(*,*) 'xv(pp)= ',xv(:,i)
       !enddo
       
       ! 1 Delete ghosts and Set velocity to zero
       !call delete_particles
       xv(4:6,:) = 0
       
      ! do i=1,20
      !    write(*,*) 'xv(pp)= ',xv(:,i)
      ! enddo


       ! 2 Get the force on all particles
       call particle_mesh
       
       ! 3 Now xv(4:6:pp) is velocity, Force/m on pp is xv(4:6,pp)/dt/mass_p
       
       dv(1:3,:) = xv(4:6,:) 

       do i=1,20
          write(*,*) 'xv(pp)= ',xv(:,i)
       !   write(*,*) 'dxv(pp)= ',dxv(:,i)          
       enddo
       
       ! 4 Set the velocities to zero again
       xv(4:6,:) = 0
       !do i=1,20
       !   write(*,*) 'xv(pp)= ',xv(:,i)
       !enddo
      
       ! 5 Remove a particle and keep track of its position (create a hole)
       
       call random_number(pp_hole)
       write(*,*)'pp_hole=',pp_hole
       pp_hole = pp_hole*np_local
       if(pp_hole < 1) pp_hole = pp_hole*np_local
       write(*,*)'pp_hole=',ceiling(pp_hole)       
       x_hole(:)=xv(1:3,ceiling(pp_hole))
       write(*,*) 'x_hole= ',x_hole      
       xv(1,ceiling(pp_hole)) = -1.000
       write(*,*) 'x_delete= ',xv(1:3,ceiling(pp_hole))            
       write(*,*) 'np_local before =', np_local
       call delete_particles
       write(*,*) 'np_local after =', np_local
       
       ! must associate initial velocity with the new order of particle
       ! after deleting one
       dv(:,ceiling(pp_hole)) = dv(:,np_local+1)

       ! 6 Compute the force again
       call particle_mesh       
       ! Now xv(4:6:pp) is new velocity.              
       
       ! 7 Compute change in velocity
       dv(1:3,:) = dv(1:3,:) - xv(4:6,:)

       do i=1,20
          write(*,*) 'dv(pp)= ',xv(1:3,i),dv(:,i)
       enddo

       do i = 1,np_local

          !sim force = dv/dt
          F_sim=dv(1:3,i)/dt/mass_p
          !write(*,*) 'F_sim= ',F_sim

          !theoretical force = 1/r**2
          r = xv(1:3,i) - x_hole
          do j=1,3
             if (r(j) < -real(nf_physical_dim/2,kind=4)) &
                  r(j) = r(j)+real(nf_physical_dim,kind=4) 
             if (r(j) > real(nf_physical_dim/2,kind=4)) &
                  r(j) = r(j)-real(nf_physical_dim,kind=4)
          enddo
 
          magr=sqrt(r(1)**2+r(2)**2+r(3)**2)
          !print *,'current seperation:',r,magr
          F=-G*r/magr**3.0
          magF=sqrt(F(1)**2+F(2)**2+F(3)**2)
          acc=F*mass_p
          v=acc*dt

          !! NEED velocity after fine mesh update for F_sim_fine
          magF_sim=sqrt(F_sim(1)**2+F_sim(2)**2+F_sim(3)**2)
          magF_sim_r=(F_sim(1)*F(1)*(-1.0) + &
               F_sim(2)*F(2)*(-1.0) + &
               F_sim(3)*F(3)*(-1.0))/magF
          magF_sim_t=sqrt(magF_sim**2-magF_sim_r**2)
          del_F=magF-magF_sim
          frac_err=del_F/magF
          
          open(41,file='report_force.dat',position = 'append') 
          write(41,'(6f16.8)') magr, magF_sim, magF, frac_err, &
                             magF_sim_r,magF_sim_t
          close(41)
 

       enddo
      
    endif
    
  end subroutine report_force 
