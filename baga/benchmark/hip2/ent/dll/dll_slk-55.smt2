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








































































































































(declare-fun p () node2)
(declare-fun v10prm () Int)
(declare-fun tmp1prm () node2)
(declare-fun n () Int)
(declare-fun aprm () Int)
(declare-fun a () Int)
(declare-fun xprm () node2)
(declare-fun x () node2)


(assert 
(and 
;lexvar(distinct aprm v10prm)
(= v10prm 1)
(= tmp1prm nil)
(< 0 a)
(< a n)
(= aprm a)
(= xprm x)
(tobool  
(dll x p n)
 )
)
)

(assert (not 
;lexvar
))

(check-sat)