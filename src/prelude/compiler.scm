;; Copyright (c) 2013-2014 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define (compile->scheme tokenizer)
  (let loop ((v (slogan tokenizer))
             (exprs '()))
    (if (not (eof-object? v))
        (if (not (void? v)) 
            (loop (slogan tokenizer)
                  (cons v exprs))
            (loop (slogan tokenizer) exprs))
        (reverse exprs))))

(define compile
  (lambda (script-name #!key 
		       (assemble #f)
		       (exe #f))      
    (with-exception-catcher
     display-exception
     (lambda ()
       (let ((out-file-name (string-append script-name *scm-extn*)))
	 (call-with-output-file out-file-name
	   (lambda (out-port)
	     (call-with-input-file (if (not (string-endswith? script-name *slgn-extn*)) 
				       (string-append script-name *slgn-extn*)
				       script-name)
	       (lambda (port)
		 (let loop ((exprs (compile->scheme (make-tokenizer port compile-mode: (or assemble exe)))))
		   (if (not (null? exprs))
		       (begin (write (car exprs) out-port)
			      (newline out-port)
			      (loop (cdr exprs)))))))))
	 (if (or assemble exe)
	     (let ((build-cmd (if exe 
				  (string-append "../platform/gsc/gsc/gsc -o "
						 (string-append script-name *exe-extn*)
						 " -exe "
						 (string-append *prelude-root* "/*.scm ")
						 out-file-name)
				  (string-append "../platform/gsc/gsc/gsc " out-file-name))))
	       (if (zero? (shell-command build-cmd))
		   (begin (delete-file out-file-name)
			  #t)
		   #f))
	     #t))))))

(define (repl tokenizer #!optional (prompt "slogan> "))
  (display prompt) 
  (if (slogan-display
       (with-exception-catcher 
        display-exception
        (lambda () 
          (let ((expr (slogan tokenizer)))
            (eval expr)))))
      (newline))
  (repl tokenizer prompt))
