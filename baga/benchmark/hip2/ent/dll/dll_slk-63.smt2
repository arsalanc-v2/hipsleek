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








































































































































(declare-fun Anon23 () Int)
(declare-fun Anon21 () Int)
(declare-fun v15prm () node2)
(declare-fun self16 () node2)
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
(declare-fun flted25 () Int)
(declare-fun flted23 () Int)
(declare-fun q20 () node2)


(assert 
(and 
;lexvar(= v15prm q18)
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
(tobool (ssep 
(pto self16 (sref (ref val Anon23) (ref prev p19) (ref next q20) ))
(dll q20 self16 flted25)
(pto xprm (sref (ref val Anon21) (ref prev p17) (ref next q18) ))
) )
)
)

(assert (not 
(and 
(tobool  
(pto v15prm (sref (ref val val14prm) (ref prev prev14prm) (ref next next14prm) ))
 )
)
))

(check-sat)