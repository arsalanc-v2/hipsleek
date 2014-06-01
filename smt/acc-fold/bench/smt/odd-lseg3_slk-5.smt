(set-logic QF_S)

(declare-sort node 0)
(declare-fun nxt () (Field node node))

(define-fun olseg ((?in node) (?p node))
Space (tospace
(or
(and 
(tobool (ssep 
(pto ?in  (ref nxt ?p))
) )
)(exists ((?a node)(?b node)) (tobool (ssep (ssep (pto ?in  (ref nxt ?a)) (pto ?a  (ref nxt ?b))) (olseg ?b ?p))))
)))











(declare-fun p () node)
(declare-fun a () node)
(declare-fun b () node)


(assert 
(and 
(tobool (ssep 
(olseg b p)
(pto p  (ref nxt a))
(pto a  (ref nxt b))
emp
) )
)
)

(assert (not 
(and 
(tobool (ssep 
(olseg b b)
emp
) )
)
))

(check-sat)