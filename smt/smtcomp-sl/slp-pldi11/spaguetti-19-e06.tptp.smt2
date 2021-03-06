(set-logic QF_S)
(set-info :source |
A. Rybalchenko and J. A. Navarro Pérez.
[Separation Logic + Superposition Calculus = Heap Theorem Prover]
[PLDI 2011]
http://navarroj.com/research/papers.html#pldi11
|)
(set-info :smt-lib-version 2.0)
(set-info :category "random") 
(set-info :status unsat)


(declare-sort Sll_t 0)

(declare-fun f () (Field Sll_t Sll_t))

(define-fun ls ((?in Sll_t) (?out Sll_t)) Space
(tospace (or (= ?in ?out)
(exists ((?u Sll_t))
(tobool
(ssep (pto ?in (ref f ?u)) (ls ?u ?out)
))))))

(declare-fun nil () Sll_t)

(declare-fun x_emp () Sll_t)
(declare-fun y_emp () Sll_t)
(declare-fun z_emp () Sll_t)
(declare-fun t_emp () Sll_t)
(declare-fun x0 () Sll_t)
(declare-fun x1 () Sll_t)
(declare-fun x2 () Sll_t)
(declare-fun x3 () Sll_t)
(declare-fun x4 () Sll_t)
(declare-fun x5 () Sll_t)
(declare-fun x6 () Sll_t)
(declare-fun x7 () Sll_t)
(declare-fun x8 () Sll_t)
(declare-fun x9 () Sll_t)
(declare-fun x10 () Sll_t)
(declare-fun x11 () Sll_t)
(declare-fun x12 () Sll_t)
(declare-fun x13 () Sll_t)
(declare-fun x14 () Sll_t)
(declare-fun x15 () Sll_t)
(declare-fun x16 () Sll_t)
(declare-fun x17 () Sll_t)
(declare-fun x18 () Sll_t)
(declare-fun x19 () Sll_t)
(declare-fun x20 () Sll_t)
(declare-fun x21 () Sll_t)
(declare-fun x22 () Sll_t)
(declare-fun x23 () Sll_t)
(declare-fun alpha0 () SetLoc)
(declare-fun alpha1 () SetLoc)
(declare-fun alpha2 () SetLoc)
(declare-fun alpha3 () SetLoc)
(declare-fun alpha4 () SetLoc)
(declare-fun alpha5 () SetLoc)
(declare-fun alpha6 () SetLoc)
(declare-fun alpha7 () SetLoc)
(declare-fun alpha8 () SetLoc)
(declare-fun alpha9 () SetLoc)
(declare-fun alpha10 () SetLoc)
(declare-fun alpha11 () SetLoc)
(declare-fun alpha12 () SetLoc)
(declare-fun alpha13 () SetLoc)
(declare-fun alpha14 () SetLoc)
(assert
  (and 
    (= nil nil)
(distinct x6 x11 )
(distinct x6 x18 )
(distinct x6 x13 )
(distinct x6 x9 )
(distinct x11 x13 )
(distinct x11 x14 )
(distinct x3 x11 )
(distinct x3 x4 )
(distinct x3 x10 )
(distinct x7 x17 )
(distinct x12 x19 )
(distinct x12 x16 )
(distinct x15 x18 )
(distinct x14 x17 )
(distinct x8 x10 )
(distinct x8 x13 )
(distinct x8 x17 )
(distinct x4 x13 )
(distinct x1 x8 )
(distinct x1 x11 )
(distinct x1 x3 )
(distinct x1 x14 )
(distinct x1 x15 )
(distinct x16 x18 )
(distinct x16 x19 )
(distinct x13 x19 )
(distinct x13 x15 )
(distinct x10 x12 )
(distinct x5 x13 )
    (tobool  (ssep  (index alpha0 (ls x19 x10 )) (ssep  (index alpha1 (ls x10 x3 )) (ssep  (index alpha2 (ls x18 x3 )) (ssep  (index alpha3 (ls x2 x18 )) (ssep  (index alpha4 (ls x2 x1 )) (ssep  (index alpha5 (ls x12 x9 )) (ssep  (index alpha6 (ls x9 x13 )) (ssep  (index alpha7 (ls x7 x8 )) (ssep  (index alpha8 (ls x3 x17 )) (ssep  (index alpha9 (ls x3 x16 ))(ssep (pto x_emp (ref f y_emp)) (pto z_emp (ref f t_emp))))))))))))))
  )
)
(assert
  (not
    (and (distinct x1 x1 )    (tobool (ssep (pto x_emp (ref f y_emp)) (pto z_emp (ref f t_emp))))
)  ))

(check-sat)
