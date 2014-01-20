;; Copyright (c) 2013-2014 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define (make-tokenizer port #!key (compile-mode #f))
  (let ((current-token #f)
        (lookahead-stack '()))
    (lambda (msg . args)
      (case msg
        ((peek) 
         (if (not current-token)
             (if (= 0 (length lookahead-stack))
                 (set! current-token (next-token port))
                 (begin (set! current-token (car lookahead-stack))
                        (set! lookahead-stack (cdr lookahead-stack)))))
         current-token)
        ((next)
         (if (not current-token)
             (if (= 0 (length lookahead-stack))
                 (next-token port)
                 (let ((tmp (car lookahead-stack)))
                   (set! lookahead-stack (cdr lookahead-stack))
                   tmp))
             (let ((tmp current-token))
               (set! current-token #f)
               tmp)))
        ((put)
         (if current-token
             (begin (set! lookahead-stack (cons current-token lookahead-stack))
                    (set! current-token #f)))
         (set! lookahead-stack (cons (car args) lookahead-stack)))
        ((compile-mode?) compile-mode)
        (else (error "tokenizer received unknown message: " msg))))))

(define (next-token port)
  (let ((c (peek-char port)))
    (if (eof-object? c)
        c
        (let ((opr (single-char-operator? c)))
          (if opr
              (begin (read-char port)
                     (if (char-comment-start? c)
                         (skip-comment port)
                         (cdr opr)))
              (cond ((char-whitespace? c)
                     (skip-whitespace port)
                     (next-token port))
                    ((char-numeric? c)
                     (read-number port #f))
                    ((multi-char-operator? c)
                     (read-multi-char-operator port))
                    ((char=? c #\")
                     (read-string port))
		    ((char=? c #\')
		     (read-character port))
                    ((char=? c #\.)
                     (read-char port)
                     (if (char-numeric? (peek-char port))
                         (read-number port #t)
                         '*period*))
                    (else (read-name port))))))))

(define *single-char-operators* (list (cons #\+ '*plus*)
                                      (cons #\- '*minus*)
                                      (cons #\/ '*backslash*)
                                      (cons #\* '*asterisk*)
                                      (cons #\( '*open-paren*)
                                      (cons #\) '*close-paren*)
                                      (cons #\{ '*open-brace*)
                                      (cons #\} '*close-brace*)
                                      (cons #\[ '*open-bracket*)
                                      (cons #\] '*close-bracket*)
                                      (cons #\, '*comma*)
                                      (cons #\: '*colon*)
                                      (cons #\; '*semicolon*)))

(define (math-operator? sym)
  (or (eq? sym '*plus*)
      (eq? sym '*minus*)
      (eq? sym '*backslash*)
      (eq? sym '*asterisk*)))

(define (single-char-operator? c)
  (assoc c *single-char-operators*))

(define (multi-char-operator? c)
  (or (char=? c #\=)
      (char=? c #\<)
      (char=? c #\>)))

(define (fetch-operator port 
                        suffix
                        suffix-opr
                        opr)
  (read-char port)
  (if (char=? (peek-char port) suffix)
      (begin (read-char port)
             suffix-opr)
      opr))

(define (read-multi-char-operator port)
  (let ((c (peek-char port)))
    (cond ((char=? c #\=)
           (fetch-operator port #\= '*equals* '*assignment*))
          ((char=? c #\<)
           (fetch-operator port #\= '*less-than-equals* '*less-than*))
          ((char=? c #\>)
           (fetch-operator port #\= '*greater-than-equals* '*greater-than*))
          (else
           (error "expected a valid operator. unexpected character: " (read-char port))))))

(define (read-number port prefix-period)
  (let loop ((c (peek-char port))
             (result (if prefix-period '(#\.) '())))
    (if (char-valid-in-number? c)
        (begin (read-char port)
               (loop (peek-char port)
                     (cons c result)))
        (let ((n (string->number (list->string (reverse result)))))
          (if (not n)
              (error "read-number failed. invalid number format.")
              n)))))

(define (char-valid-in-number? c)
  (or (char-numeric? c)
      (char=? #\e c)
      (char=? #\E c)
      (char=? #\. c)))

(define (skip-whitespace port)
  (let loop ((c (peek-char port)))
    (if (eof-object? c)
        c
        (if (char-whitespace? c)
            (begin (read-char port)
                   (loop (peek-char port)))))))

(define (char-valid-name-start? c)
  (and (char? c) 
       (or (char-alphabetic? c)
           (char=? c #\_)
           (char=? c #\$)
           (char=? c #\?)
           (char=? c #\&))))

(define (char-valid-in-name? c)
  (and (char? c) 
       (or (char-valid-name-start? c)
           (char-numeric? c))))

(define (read-name port)
  (if (char-valid-name-start? (peek-char port))
      (let loop ((c (peek-char port))
                 (result '()))
        (if (char-valid-in-name? c)
            (begin (read-char port)
                   (loop (peek-char port)
                         (cons c result)))
            (string->symbol (list->string (reverse result)))))
      (error "read-name failed at " (peek-char port))))

(define (read-string port)
  (let ((c (read-char port)))
    (if (char=? c #\")
        (let loop ((c (peek-char port))
                   (result '()))
          (if (char? c)
              (cond ((char=? c #\")
                     (read-char port)
                     (list->string (reverse result)))
                    ((char=? c #\\)
                     (read-char port)
                     (set! c (read-char port))
                     (loop (peek-char port) (cons c result)))
                    (else 
                     (set! c (read-char port))
                     (loop (peek-char port) (cons c result))))
              (error "string not terminated.")))
        (error "read-string failed at " c))))

(define (char-comment-start? c) (char=? c #\/))
(define (char-comment-part? c) (or (char-comment-start? c) 
                                   (char=? c #\*)))

(define (skip-comment port)
  (if (char-comment-part? (peek-char port))
      (let ((c (read-char port)))
        (if (char-comment-start? c)
            (skip-line-comment port)
            (skip-block-comment port))
        '*semicolon*)
      '*backslash*))

(define (skip-line-comment port)
  (let loop ((c (peek-char port)))
    (if (and (char? c)
             (not (char=? c #\newline)))
        (begin (read-char port)
               (loop (peek-char port))))))

(define (skip-block-comment port)
  (let loop ((c (peek-char port)))
    (if (not (eof-object? c))
        (begin (read-char port)
               (if (char=? c #\*)
                   (if (not (char=? (read-char port) #\/))
                       (loop (peek-char port)))
                   (loop (peek-char port)))))))

(define (read-character port)
  (if (char=? (read-char port) #\')
      (let ((c (read-char port)))
	(if (not (char=? (read-char port) #\'))
	    (error "character constant not terminated. " c)
	    c))
      (error "not a character literal.")))