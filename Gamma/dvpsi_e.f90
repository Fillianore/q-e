!
! Copyright (C) 2003 PWSCF group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
!----------------------------------------------------------------------
subroutine dvpsi_e(kpoint,ipol)
  !----------------------------------------------------------------------
  !
  ! Calculates x * psi_k  for each k-points and for the 3 polarizations
  ! Requires on input: vkb, evc, igk
  !
#include "machine.h"
  use parameters, only: DP
  use pwcom
  USE wavefunctions,  ONLY: evc
  use rbecmod
  use cgcom
  !
  implicit none
  integer :: kpoint, ipol
  integer :: i,l, na,nt, ibnd,jbnd, info, ih,jkb, iter
  real(kind=DP) :: upol(3,3)
  real(kind=DP), allocatable :: gk(:,:), q(:), ps(:,:,:), overlap(:,:), &
       bec1(:,:)
  complex(kind=DP), allocatable :: dvkb(:,:), dvkb1(:,:), work(:,:), &
       &           gr(:,:), h(:,:)
  logical:: precondition, orthonormal,startwith0
  external H_h
  data upol /1.0,0.0,0.0, 0.0,1.0,0.0, 0.0,0.0,1.0/
  !
  call start_clock('dvpsi_e')
  !
  allocate  ( gk   ( 3, npwx))    
  allocate  ( dvkb ( npwx, nkb))    
  allocate  ( dvkb1( npwx, nkb))    
  allocate  ( bec1 ( nkb, nbnd))    
  allocate  ( ps   ( nkb, nbnd, 2))    
  !
  do i = 1,npw
     gk(1,i) = (xk(1,kpoint)+g(1,igk(i)))*tpiba
     gk(2,i) = (xk(2,kpoint)+g(2,igk(i)))*tpiba
     gk(3,i) = (xk(3,kpoint)+g(3,igk(i)))*tpiba
     g2kin(i)= gk(1,i)**2 + gk(2,i)**2 + gk(3,i)**2
  end do
  !
  !  this is  the kinetic contribution to [H,x]:  -2i (k+G)_ipol * psi
  !
  do ibnd = 1,nbnd
     do i = 1,npw
        dpsi(i,ibnd) = gk(ipol,i)*(0.0,-2.0) * evc(i,ibnd)
     end do
  end do
  !
  do i = 1,npw
     if (g2kin(i).gt.1.0d-10) then
        gk(1,i) = gk(1,i)/sqrt(g2kin(i))
        gk(2,i) = gk(2,i)/sqrt(g2kin(i))
        gk(3,i) = gk(3,i)/sqrt(g2kin(i))
     endif
  end do
  !
  ! and these are the contributions from nonlocal pseudopotentials
  ! ( upol(3,3) are the three unit vectors along x,y,z)
  !
  call gen_us_dj(kpoint,dvkb)
  call gen_us_dy(kpoint,upol(1,ipol),dvkb1)
  !
  do jkb = 1, nkb
     do i = 1,npw
        dvkb(i,jkb) =(0.d0,-1.d0)*(dvkb1(i,jkb) + dvkb(i,jkb)*gk(ipol,i))
     end do
  end do
  !
  call pw_gemm ('Y', nkb, nbnd, npw,  vkb, npwx, evc, npwx, becp, nkb)
  call pw_gemm ('Y', nkb, nbnd, npw, dvkb, npwx, evc, npwx, bec1, nkb)
  !
  jkb = 0
  do nt=1, ntyp
     do na = 1,nat
        if (nt.eq.ityp(na)) then
           do ih=1,nh(nt)
              jkb=jkb+1
              do ibnd = 1,nbnd
                 ps(jkb,ibnd,1) = bec1(jkb,ibnd)*dvan(ih,ih,nt)
                 ps(jkb,ibnd,2) = becp(jkb,ibnd)*dvan(ih,ih,nt)
              enddo
           end do
        end if
     end do
  end do
  !
  if (jkb.ne.nkb) call errore('dvpsi_e','unexpected error',1)
  !
  call DGEMM ('N', 'N', 2*npw, nbnd, nkb,-1.d0, vkb, &
       2*npwx, ps(1,1,1), nkb, 1.d0, dpsi, 2*npwx)
  call DGEMM ('N', 'N', 2*npw, nbnd, nkb, 1.d0,dvkb, &
       2*npwx, ps(1,1,2), nkb, 1.d0, dpsi, 2*npwx)
  !
  deallocate(ps)
  deallocate(bec1)
  deallocate(dvkb1)
  deallocate(dvkb)
  deallocate(gk)
  !
  !   dpsi contains now [H,x] psi_v  for the three cartesian polarizations.
  !   Now solve the linear systems (H-e_v)*(x*psi_v) = [H,x]*psi_v
  !
  allocate  ( overlap( nbnd, nbnd))    
  allocate  ( work( npwx, nbnd))    
  allocate  ( gr( npwx, nbnd))    
  allocate  ( h ( npwx, nbnd))    
  allocate  ( q ( npwx))    
  !
  orthonormal = .false.
  precondition= .true.
  !
  if (precondition) then
     do i = 1,npw
        q(i) = 1.0/max(1.d0,g2kin(i))
     end do
     call zvscal(npw,npwx,nbnd,q,evc,work)
     call pw_gemm ('Y',nbnd, nbnd, npw, work, npwx, evc, npwx, overlap, nbnd)
     call DPOTRF('U',nbnd,overlap,nbnd,info)
     if (info.ne.0) call errore('solve_ph','cannot factorize',info)
  end if
  !
  startwith0= .true.
  dvpsi(:,:) = (0.d0, 0.d0)
  !
  call cgsolve (H_h,npw,evc,npwx,nbnd,overlap,nbnd,   &
       orthonormal,precondition,q,startwith0,et(1,kpoint),&
       dpsi,gr,h,dpsi,work,niter_ph,tr2_ph,iter,dvpsi)
  !
  deallocate(q)
  deallocate(h)
  deallocate(gr)
  deallocate(work)
  deallocate(overlap)
  !
  call stop_clock('dvpsi_e')
  !
  return
end subroutine dvpsi_e
