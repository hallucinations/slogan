(load (string-append *prelude-root* "/prelude/prelude.i.scm"))
(define lst (pair "a" "b"))
(println (first lst))
(println (rest lst))
(set! lst (pair (list 1 2 3) "hello, world"))
(println (first lst))
(println (rest lst))