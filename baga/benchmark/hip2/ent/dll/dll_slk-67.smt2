(set-logic QF_S)
(set-info :source |  Sleek solver
  http://loris-7.ddns.comp.nus.edu.sg/~project/hip/
|)

(set-info :smt-lib-version 2.0)
(set-info :category "crafted")
(set-info :status unsat)


(declare-sort node2 0)
(declare-fun val () (Field node2 Int))
(declare-fun prev () (Field node2 node2))
(declare-fun next () (Field node2 node2))

(define-fun dll ((?in node2) (?p node2) (?n Int))
Space (tospace
(or
(and 
(= ?in nil)
(= ?n 0)

)(exists ((?p_41 node2)(?self_42 node2)(?flted_12_40 Int))(and 
(= (+ ?flted_12_40 1) ?n)
(= ?p_41 ?p)
(= ?self_42 ?in)
(tobool (ssep 
(pto ?in (sref (ref val ?Anon_14) (ref prev ?p_41) (ref next ?q) ))
(dll ?q ?self_42 ?flted_12_40)
) )
)))))








































































































































(declare-fun Anon21 () Int)
(declare-fun Anon23 () Int)
(declare-fun Anon25 () Int)
(declare-fun q22 () node2)
(declare-fun tmpprm () node2)
(declare-fun prev3 () node2)
(declare-fun self18 () node2)
(declare-fun q18 () node2)
(declare-fun x () node2)
(declare-fun a () Int)
(declare-fun tmp1prm () node2)
(declare-fun aprm () Int)
(declare-fun xprm () node2)
(declare-fun p17 () node2)
(declare-fun p () node2)
(declare-fun n () NUM)
(declare-fun p19 () node2)
(declare-fun self14 () node2)
(declare-fun flted23 () Int)
(declare-fun q20 () node2)
(declare-fun p21 () node2)
(declare-fun self16 () node2)
(declare-fun flted27 () Int)
(declare-fun flted25 () Int)


(assert 
(and 
;lexvar(= tmpprm q20)
(= prev3 p21)
(= self18 q20)
(= self16 q18)
(= xprm x)
(= aprm a)
(< a n)
(< 0 a)
(= tmp1prm nil)
(= aprm 1)
(= self14 xprm)
(= p17 p)
(= (+ flted23 1) n)
(= p19 self14)
(= (+ flted25 1) flted23)
(distinct q20 nil)
(= p21 self16)
(= (+ flted27 1) flted25)
(tobool (ssep 
(dll q22 self18 flted27)
(pto xprm (sref (ref val Anon21) (ref prev p17) (ref next q18) ))
(pto q18 (sref (ref val Anon23) (ref prev p19) (ref next q20) ))
(pto self18 (sref (ref val Anon25) (ref prev xprm) (ref next q22) ))
) )
)
)

(assert (not 
(and 
(tobool  
(pto xprm (sref (ref val val18prm) (ref prev prev18prm) (ref next next18prm) ))
 )
)
))

(check-sat)