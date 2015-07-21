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








































































































































(declare-fun Anon31 () Int)
(declare-fun Anon29 () Int)
(declare-fun next8 () node2)
(declare-fun self24 () node2)
(declare-fun q26 () node2)
(declare-fun a () Int)
(declare-fun aprm () Int)
(declare-fun xprm () node2)
(declare-fun p27 () node2)
(declare-fun p29 () node2)
(declare-fun self22 () node2)
(declare-fun flted35 () Int)
(declare-fun flted33 () Int)
(declare-fun q28_3769 () node2)
(declare-fun q28 () node2)
(declare-fun x () node2)
(declare-fun p () node2)
(declare-fun n () Int)


(assert 
(and 
;lexvar(= next8 q26)
(= self24 q26)
(= xprm x)
(= aprm a)
(< a n)
(< 0 a)
(= aprm 1)
(= self22 xprm)
(= p27 p)
(= (+ flted33 1) n)
(= p29 self22)
(= (+ flted35 1) flted33)
(= q28 nil)
(not )(tobool (ssep 
(pto self24 (sref (ref val Anon31) (ref prev p29) (ref next q28) ))
(dll q28 self24 flted35)
(pto xprm (sref (ref val Anon29) (ref prev p27) (ref next q28) ))
) )
)
)

(assert (not 
(exists ((p35 node2)(flted40 Int))(and 
(= p35 p)
(= (+ flted40 1) n)
(<= 0 n)
(tobool  
(dll x p35 flted40)
 )
))
))

(check-sat)