;; Copyright (c) 2013-2014 by Vijay Mathew Pandyalakal, All Rights Reserved.

;; forward references:
(define compile #f) ;; defined in compiler.ss

(define (slogan tokenizer)
  (expression/statement tokenizer))

(define (import tokenizer script-name)
  (if (compile (if (symbol? script-name) 
                   (symbol->string script-name) 
                   script-name) 
               assemble: (tokenizer 'compile-mode?))
      (if (tokenizer 'compile-mode?)
          `(load ,script-name)
          `(load ,(string-append script-name *scm-extn*)))))

(define (expression/statement tokenizer)
  (if (eof-object? (tokenizer 'peek))
      (tokenizer 'next)
      (let ((v (statement tokenizer)))
        (if (not v)
            (set! v (expression tokenizer)))
        (assert-semicolon tokenizer)
        v)))

(define (statement tokenizer)
  (if (eq? (tokenizer 'peek) '*semicolon*)
      '#!void
      (import-stmt tokenizer)))

(define (assert-semicolon tokenizer)
  (let ((token (tokenizer 'peek)))
    (if (or (eq? token '*semicolon*)
            (eq? token '*close-brace*))
        (if (eq? token '*semicolon*)
            (tokenizer 'next))
        (error "statement not properly terminated."))))

(define (import-stmt tokenizer)
  (cond ((eq? (tokenizer 'peek) 'import)
         (tokenizer 'next)
         (import tokenizer (tokenizer 'next)))
        (else
         (assignment-stmt tokenizer))))

(define (assignment-stmt tokenizer)
  (if (name? (tokenizer 'peek))
      (let ((sym (tokenizer 'next)))
        (if (eq? sym 'var)
            (define-stmt tokenizer)
            (cond ((reserved-name? sym)
                   (tokenizer 'put sym)
                   #f)
                  ((eq? (tokenizer 'peek) '*assignment*)
                   (set-stmt sym tokenizer))
                  (else (tokenizer 'put sym) 
                        #f))))
      #f))

(define (define-stmt tokenizer)
  (if (variable? (tokenizer 'peek))
      (if (reserved-name? (tokenizer 'peek))
          (error "reserved name cannot be used as variable name - " (tokenizer 'next))
          (var-def-set (tokenizer 'next) tokenizer #t))
      (error "expected variable name instead of " (tokenizer 'peek))))

(define (set-stmt sym tokenizer)
  (var-def-set sym tokenizer #f))

(define (var-def-set sym tokenizer def)
  (if (eq? (tokenizer 'peek) '*assignment*)
      (begin (tokenizer 'next)
             (list (if def 'define 'set!) sym (expression tokenizer)))
      (error "expected assignment instead of " (tokenizer 'peek))))

(define (expression tokenizer)
  (let ((expr (binary-expr tokenizer)))
    (let loop ((expr expr)) 
      (if (eq? (tokenizer 'peek) '*open-paren*)
          (loop (func-call-expr expr tokenizer))
          expr))))

(define (if-expr tokenizer)
  (cond ((eq? (tokenizer 'peek) 'if)
         (tokenizer 'next)
         (let ((expr (cons 'if (list (expression tokenizer)
                                     (block-expr tokenizer)))))
           (if (eq? (tokenizer 'peek) 'else)
               (begin (tokenizer 'next)
                      (if (eq? (tokenizer 'peek) 'if)
                          (append expr (list (if-expr tokenizer)))
                          (append expr (list (block-expr tokenizer)))))
               expr)))
        (else #f)))

(define (block-expr tokenizer)
  (if (not (eq? (tokenizer 'peek) '*open-brace*))
      (error "expected block start instead of " (tokenizer 'next))
      (begin (tokenizer 'next)
             (let loop ((expr (cons 'let (cons '() '())))
                        (count 0))
               (let ((token (tokenizer 'peek)))
                 (if (eq? token '*close-brace*)
                     (begin (tokenizer 'next)
                            (if (zero? count)
                                (append expr (list '#!void))
                                expr))
                     (loop (append expr (list (expression/statement tokenizer)))
                           (+ 1 count))))))))

(define (binary-expr tokenizer)
  (let loop ((expr (cmpr-expr tokenizer)))
    (if (and-or-opr? (tokenizer 'peek))
        (case (tokenizer 'next)
          ((and) (loop (swap-operands (append (and-expr tokenizer) (list expr)))))
          ((or) (loop (swap-operands (append (or-expr tokenizer) (list expr))))))
        expr)))
  
(define (cmpr-expr tokenizer)
  (let loop ((expr (addsub-expr tokenizer)))
    (if (cmpr-opr? (tokenizer 'peek))
        (case (tokenizer 'next)
          ((*equals*) (loop (swap-operands (append (eq-expr tokenizer) (list expr)))))
          ((*less-than*) (loop (swap-operands (append (lt-expr tokenizer) (list expr)))))
          ((*greater-than*) (loop (swap-operands (append (gt-expr tokenizer) (list expr)))))
          ((*less-than-equals*) (loop (swap-operands (append (lteq-expr tokenizer) (list expr)))))
          ((*greater-than-equals*) (loop (swap-operands (append (gteq-expr tokenizer) (list expr))))))
        expr)))

(define (addsub-expr tokenizer)
  (let loop ((expr (term-expr tokenizer)))
    (if (add-sub-opr? (tokenizer 'peek))
        (case (tokenizer 'next)
          ((*plus*) (loop (swap-operands (append (add-expr tokenizer) (list expr)))))
          ((*minus*) (loop (swap-operands (append (sub-expr tokenizer) (list expr))))))
        expr)))

(define (factor-expr tokenizer)
  (let ((token (tokenizer 'peek)))
    (if (eq? token '*open-paren*)
        (begin (tokenizer 'next)
               (let ((expr (expression tokenizer)))
                 (if (not (eq? (tokenizer 'peek) '*close-paren*))
                     (begin (error "expected closing-parenthesis instead of " (tokenizer 'next))
                            #f)
                     (begin (tokenizer 'next)
                            expr))))
        (let ((expr (if-expr tokenizer)))
          (if expr
              expr
              (let-expr tokenizer))))))

(define (literal-expr tokenizer)
  (let ((expr (func-def-expr tokenizer)))
    (if expr
        expr
        (let ((token (tokenizer 'peek)))
          (cond ((or (number? token)
                     (string? token)
		     (char? token))
                 (slogan-repr->scheme-repr (tokenizer 'next)))
                ((add-sub-opr? token)
                 (tokenizer 'next)
                 (let ((sub (eq? token '*minus*))
                       (expr (literal-expr tokenizer)))
                   (if sub 
                       (list '- expr)
                       expr)))
                ((variable? token)
                 (if (slogan-symbol? token)
                     `(quote ,(tokenizer 'next))
                     (let ((var (tokenizer 'next)))
                       (if (eq? (tokenizer 'peek) '*period*)
                           (begin (tokenizer 'next)
                                  (record-member-access var tokenizer))
                           (slogan-repr->scheme-repr var)))))
                ((eq? token '*open-bracket*)
                 (list-literal tokenizer))
                ((eq? token '*open-brace*)
                 (block-expr tokenizer))
                ((eq? token '*hash*)
                 (array-literal tokenizer))
                (else
                 (error "invalid literal expression: " (tokenizer 'next))))))))

(define (list-literal tokenizer)
  (tokenizer 'next)
  (let loop ((result (list 'list)))
    (let ((token (tokenizer 'peek)))
      (if (eq? token '*close-bracket*)
          (begin (tokenizer 'next)
                 (reverse result))
          (let ((expr (expression tokenizer)))
            (assert-comma-separator tokenizer '*close-bracket*)
            (loop (cons expr result)))))))

(define (array-literal tokenizer)
  (tokenizer 'next)
  (if (eq? (tokenizer 'peek) '*open-bracket*)
      (begin (tokenizer 'next)
             (let loop ((expr (list 'vector))
                        (token (tokenizer 'peek)))
               (cond ((eq? token '*close-bracket*)
                      (tokenizer 'next)
                      (reverse expr))
                     (else 
                      (let ((e (expression tokenizer)))
                        (assert-comma-separator tokenizer '*close-bracket*)
                        (loop (cons e expr) (tokenizer 'peek)))))))
      (error "invalid start of array literal. " (tokenizer 'next))))

(define (let-expr tokenizer)
  (let ((letkw (letkw? (tokenizer 'peek))))
    (cond (letkw
	   (tokenizer 'next)
	   (let loop ((result '()))
	     (let ((sym (tokenizer 'next)))
	       (if (not (name? sym))
		   (error "expected name instead of " sym))
	       (if (reserved-name? sym)
		   (error "invalid variable name " sym))
	       (if (eq? (tokenizer 'peek) '*assignment*)
		   (tokenizer 'next)
		   (error "expected assignment instead of " (tokenizer 'next)))
	       (let ((expr (expression tokenizer)))
		 (cond ((eq? (tokenizer 'peek) '*open-brace*)
			(append (list letkw) 
				(cons (append result (list (list sym expr))) 
				      (list (block-expr tokenizer)))))
		       ((eq? (tokenizer 'peek) '*comma*)
			(tokenizer 'next)
			(loop (append result (list (list sym expr)))))
		       (else (error "invalid token " (tokenizer 'next))))))))
	  (else 
	   (func-call-expr (literal-expr tokenizer) tokenizer)))))

(define (letkw? sym)
  (if (and (symbol? sym)
	   (or (eq? sym 'let)
	       (eq? sym 'letseq)
	       (eq? sym 'letrec)))
      (if (eq? sym 'letseq)
	  'let*
	  sym)
      #f))

(define (func-def-expr tokenizer)
  (if (eq? (tokenizer 'peek) 'function)
      (begin (tokenizer 'next)
             (list 'lambda 
                   (func-params-expr tokenizer)
                   (block-expr tokenizer)))
      (record-def-expr tokenizer)))

(define (func-call-expr func-val tokenizer)
  (cond ((eq? (tokenizer 'peek) '*open-paren*)
         (tokenizer 'next)
         (let ((expr (cons func-val (func-args-expr tokenizer))))
           (if (eq? (tokenizer 'peek) '*close-paren*)
               (begin (tokenizer 'next) 
                      expr)
               (error "expected closing-parenthesis after function argument list instead of " (tokenizer 'next)))))
        (else func-val)))

(define (assert-comma-separator tokenizer end-seq-char)
  (let ((token (tokenizer 'peek)))
    (if (or (eq? token '*comma*)
            (eq? token end-seq-char))
        (if (eq? token '*comma*) (tokenizer 'next))
        (error "expected comma or " end-seq-char " instead of " (tokenizer 'next)))))

(define (func-args-expr tokenizer)
  (let loop ((args '()))
    (let ((token (tokenizer 'peek)))
      (if (not (eq? token '*close-paren*))
          (cond ((variable? token)
                 (let ((sym (tokenizer 'next)))
                   (if (eq? (tokenizer 'peek) '*assignment*)
                       (begin (tokenizer 'next)
                              (let ((expr (expression tokenizer)))
                                (assert-comma-separator tokenizer '*close-paren*)
                                (loop (append args (list (slogan-variable->scheme-keyword sym) expr)))))
                       (begin (tokenizer 'put sym)
                              (let ((expr (expression tokenizer)))
                                (assert-comma-separator tokenizer '*close-paren*)
                                (loop (append args (list expr))))))))
                (else
                 (let ((expr (expression tokenizer)))
                   (assert-comma-separator tokenizer '*close-paren*)
                   (loop (append args (list expr))))))
          args))))

(define (func-params-expr tokenizer)
  (if (eq? (tokenizer 'peek) '*open-paren*)
      (begin (tokenizer 'next)
             (let loop ((params '()))
               (let ((token (tokenizer 'peek)))
                 (cond ((variable? token)
                        (let ((sym (tokenizer 'next)))
                          (if (reserved-name? sym)
                              (error "function parameter cannot be a reserved name. " sym))
                          (cond ((param-directive? sym)
                                 (loop (cons (slogan-directive->scheme-directive sym) params)))
                                ((eq? (tokenizer 'peek) '*assignment*)
                                 (tokenizer 'next)
                                 (let ((expr (expression tokenizer)))
                                   (assert-comma-separator tokenizer '*close-paren*)
                                   (loop (cons (list sym expr) params))))
                                (else 
                                 (assert-comma-separator tokenizer '*close-paren*)
                                 (loop (cons sym params))))))
                       (else 
                        (if (eq? token '*close-paren*)
                            (begin (tokenizer 'next)
                                   (reverse params))
                            (error "expected closing-parenthesis after parameter list instead of " (tokenizer 'next))))))))
      (error "expected opening-parenthesis at the start of parameter list instead of " (tokenizer 'next))))

(define (param-directive? sym)
  (memq sym '(!optional !key !rest)))

(define (record-def-expr tokenizer)
  (if (eq? (tokenizer 'peek) 'record)
      (begin (tokenizer 'next)
             (if (not (eq? (tokenizer 'peek) '*open-brace*))
                 (error "expected opening-brace instead of " (tokenizer 'next))
                 (tokenizer 'next))
             (let loop ((vars '())
                        (exprs '()))
               (let ((token (tokenizer 'peek)))
                 (cond ((variable? token)
                        (tokenizer 'next)
                        (if (eq? (tokenizer 'peek) '*colon*)
                            (begin (tokenizer 'next)
                                   (let ((expr (expression tokenizer)))
                                     (if (eq? (tokenizer 'peek) '*semicolon*)
                                         (tokenizer 'next))
                                     (loop (cons token vars) (cons expr exprs))))
                            (error "expected colon instead of " (tokenizer 'peek))))
                       ((eq? token '*close-brace*)
                        (tokenizer 'next)
                        (mk-record-expr (reverse vars) (reverse exprs)))
                       (else
                        (error "expected variable instead of " token))))))
      #f))

(define (mk-record-expr vars exprs)
  (let loop ((vs vars)
             (es exprs)
             (record-expr '(let ())))
    (if (null? vs)
        (append record-expr (list (append (list 'lambda '(*msg*)) (record-msg-handler vars))))
        (loop (cdr vs) (cdr es) (append record-expr (list (list 'define (car vs) (car es))))))))

(define (record-msg-handler vars)
  (let loop ((vars vars)
             (msg-handler '()))
    (if (null? vars)
        (list (append (list 'case '*msg*) (reverse (cons '(else (error "member not found in record.")) msg-handler))))
        (loop (cdr vars) (cons `((,(car vars)) ,(car vars)) msg-handler)))))

(define (record-member-access var tokenizer)
  (if (variable? (tokenizer 'peek))
      (let loop ((expr `(,var ',(tokenizer 'next))))
	(if (eq? (tokenizer 'peek) '*period*)
	    (begin (tokenizer 'next)
		   (if (variable? (tokenizer 'peek))
		       (loop (cons expr `(',(tokenizer 'next))))
		       (error "expected name instead of " (tokenizer 'next))))
	    expr))
      (error "expected name instead of " (tokenizer 'next))))

(define (add-expr tokenizer)
  (swap-operands (cons '+ (list (term-expr tokenizer)))))

(define (sub-expr tokenizer)
  (swap-operands (cons '- (list (term-expr tokenizer)))))

(define (mult-expr tokenizer)
  (swap-operands (cons '* (list (factor-expr tokenizer)))))

(define (div-expr tokenizer)
  (swap-operands (cons '/ (list (factor-expr tokenizer)))))

(define (eq-expr tokenizer)
  (swap-operands (cons 'equal? (list (addsub-expr tokenizer)))))

(define (lt-expr tokenizer)
  (swap-operands (cons '< (list (addsub-expr tokenizer)))))

(define (lteq-expr tokenizer)
  (swap-operands (cons '<= (list (addsub-expr tokenizer)))))

(define (gt-expr tokenizer)
  (swap-operands (cons '> (list (addsub-expr tokenizer)))))

(define (gteq-expr tokenizer)
  (swap-operands (cons '>= (list (addsub-expr tokenizer)))))

(define (and-expr tokenizer)
  (swap-operands (cons 'and (list (cmpr-expr tokenizer)))))

(define (or-expr tokenizer)
  (swap-operands (cons 'or (list (cmpr-expr tokenizer)))))

(define (term-expr tokenizer)
  (let loop ((expr (factor-expr tokenizer)))
    (if (mult-div-opr? (tokenizer 'peek))
        (case (tokenizer 'next)
          ((*asterisk*) (loop (swap-operands (append (mult-expr tokenizer) (list expr)))))
          ((*backslash*) (loop (swap-operands (append (div-expr tokenizer) (list expr))))))
        expr)))

(define (add-sub-opr? token)
  (or (eq? token '*plus*)
      (eq? token '*minus*)))

(define (mult-div-opr? token)
  (or (eq? token '*asterisk*)
      (eq? token '*backslash*)))

(define (cmpr-opr? token)
  (or (eq? token '*equals*)
      (eq? token '*less-than*)
      (eq? token '*greater-than*)
      (eq? token '*less-than-equals*)
      (eq? token '*greater-than-equals*)))

(define (and-or-opr? token)
  (or (eq? token 'and)
      (eq? token 'or)))

(define (swap-operands expr)
  (if (= 3 (length expr))
      (list (car expr) (caddr expr) (cadr expr))
      expr))

(define (variable? sym)
  (and (symbol? sym)
       (char-valid-name-start? (string-ref (symbol->string sym) 0))))

(define (reserved-name? sym)
  (and (symbol? sym)
       (memq sym '(var import if and or
                       function record
                       let letseq letrec))))

(define (name? sym) 
  (or (variable? sym)
      (reserved-name? sym)))
