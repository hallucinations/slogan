(define array make-vector)
(define array_length vector-length)
(define array_at vector-ref)
(define array_set vector-set!)
(define array_to_list vector->list)
(define list_to_array list->vector)

(define (array_exchange arr i j)
  (let ((tmp (vector-ref arr i)))
    (vector-set! arr i (vector-ref arr j))
    (vector-set! arr j tmp)))

(define (array_smallest arr #!key (test <) (start 0) (end -1))
  (let loop ((start (+ start 1))
             (end (if (= -1 end) (vector-length arr) end))
             (min start))
    (cond ((>= start end)
           min)
          ((test (vector-ref arr start) (vector-ref arr min))
           (loop (+ start 1) end start))
          (else (loop (+ start 1) end min)))))

;; sorting

(define (array_sorted? arr #!key (test <))
  (let ((len (vector-length arr)))
    (if (<= len 1)
        #t
        (let loop ((i 0))
          (cond ((< i len)
                 (if (test (vector-ref arr (+ i 1))
                           (vector-ref arr i))
                     #f
                     (loop (+ i 1))))
                (else #t))))))

(define (selection-sort arr test)
  (let ((len (vector-length arr)))
    (let loop ((i 0))
      (cond ((< i len)
             (array_exchange 
              arr i (array_smallest arr 
                                    test: test
                                    start: i
                                    end: len))
             (loop (+ i 1)))))))

(define (insertion-sort arr test)
  (let ((len (vector-length arr)))
    (let loop ((i 1))
      (cond ((< i len)
             (let inner-loop ((j i))
               (if (and (> j 0)
                        (test (vector-ref arr j)
                              (vector-ref arr (- j 1))))
                   (begin (array_exchange arr j (- j 1))
                          (inner-loop (- j 1)))))
             (loop (+ i 1)))))))

(define (quick-sort arr test)
  #f)

(define (invalid-sort arr test)
  (error "not a valid sort type."))

(define (array_sort arr #!key (test <) (type '!insertion))
  ((case type
     ((!insertion) insertion-sort)
     ((!quick) quick-sort)
     ((!merge) merge-sort)
     ((!selection) selection-sort)
     (else invalid-sort))
   arr test))