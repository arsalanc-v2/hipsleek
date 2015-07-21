(set-logic QF_S)
(set-info :source |  Sleek solver
  http://loris-7.ddns.comp.nus.edu.sg/~project/hip/
|)

(set-info :smt-lib-version 2.0)
(set-info :category "crafted")
(set-info :status unsat)


(declare-sort node2 0)
(declare-fun val () (Field node2 Int))
(declare-fun left () (Field node2 node2))
(declare-fun right () (Field node2 node2))

(declare-sort node 0)
(declare-fun val () (Field node Int))
(declare-fun next () (Field node node))

(define-fun tree1 ((?in node2) (?m Int))
Space (tospace
(or
(and 
(= ?in nil)
(= ?m 0)

)(and 
(= ?m (+ (+ ?m2 1) ?m1))
(tobool (ssep 
(pto ?in (sref (ref val ?Anon_15) (ref left ?p) (ref right ?q) ))
(tree1 ?p ?m1)
(tree1 ?q ?m2)
) )
))))

(define-fun tree ((?in node2) (?m Int) (?n Int))
Space (tospace
(or
(and 
(= ?in nil)
(= ?m 0)
(= ?n 0)

)(and 
(= ?m (+ (+ ?m2 1) ?m1))
(tobool (ssep 
(pto ?in (sref (ref val ?Anon_16) (ref left ?p) (ref right ?q) ))
(tree ?p ?m1 ?n1)
(tree ?q ?m2 ?n2)
) )
))))

(define-fun dll ((?in node2) (?p node2) (?n Int))
Space (tospace
(or
(and 
(= ?in nil)
(= ?n 0)

)(exists ((?p_33 node2)(?self_34 node2))(and 
(= ?n (+ 1 ?n1))
(= ?p_33 ?p)
(= ?self_34 ?in)
(tobool (ssep 
(pto ?in (sref (ref val ?Anon_17) (ref left ?p_33) (ref right ?q) ))
(dll ?q ?self_34 ?n1)
) )
)))))































































(declare-fun Anon6_539 () Int)
(declare-fun q2_540 () node2)
(declare-fun Anon3 () Int)
(declare-fun right () node2)
(declare-fun q1 () node2)
(declare-fun n3 () Int)
(declare-fun n () Int)
(declare-fun Anon5 () node2)
(declare-fun Anon1 () node2)
(declare-fun m1 () Int)
(declare-fun Anon4 () node2)
(declare-fun x () node2)
(declare-fun yprm () node2)
(declare-fun y () node2)
(declare-fun self2 () node2)
(declare-fun xprm () node2)
(declare-fun p1 () node2)
(declare-fun Anon () node2)
(declare-fun m () Int)
(declare-fun n2 () Int)
(declare-fun self3_538 () node2)
(declare-fun zprm () node2)
(declare-fun p2_537 () node2)
(declare-fun r1 () node2)
(declare-fun flted1 () Int)
(declare-fun n4_541 () Int)


(assert 
(exists ((p2 node2)(self3 node2)(Anon6 Int)(q2 node2)(n4 Int))(and 
;lexvar(= right q1)
(<= 0 n3)
(<= 0 m1)
(= flted1 (+ n3 m1))
(<= 0 n2)
(<= 0 n)
(= n3 n)
(= Anon5 Anon1)
(= m1 n2)
(= Anon4 self2)
(= xprm x)
(= yprm y)
(distinct xprm nil)
(not )(= self2 xprm)
(= p1 Anon)
(= m (+ 1 n2))
(distinct zprm nil)
(= self3 zprm)
(= p2 r1)
(= flted1 (+ 1 n4))
(tobool (ssep 
(pto zprm (sref (ref val Anon6) (ref left p2) (ref right q2) ))
(dll q2 self3 n4)
(pto xprm (sref (ref val Anon3) (ref left p1) (ref right zprm) ))
) )
))
)

(assert (not 
(and 
(tobool  
(pto zprm (sref (ref val val2prm) (ref left left2prm) (ref right right2prm) ))
 )
)
))

(check-sat)