(load (string-append *prelude-root* "/prelude/prelude.i.scm"))
(define square (lambda (n) (let () (* n n))))
(println (square 5))
(println (square (- 200)))
(println (square .5))
(println (square (- .5)))
