(load-relative "../libs/init.scm")
(load-relative "./base/typed-oo/lang.scm")
(load-relative "./base/typed-oo/test.scm")
(load-relative "./base/typed-oo/store.scm")
(load-relative "./base/typed-oo/interp.scm")
(load-relative "./base/typed-oo/checker.scm")
(load-relative "./base/typed-oo/environments.scm")
(load-relative "./base/typed-oo/classes.scm")
(load-relative "./base/typed-oo/static-classes.scm")
(load-relative "./base/typed-oo/data-structures.scm")
(load-relative "./base/typed-oo/static-data-structures.scm")
(load-relative "./base/typed-oo/tests.scm")

;; (define debug? (make-parameter #t))
;; these two function call on object have been done.
;; add is-static-class to test whether a symbol-name is class name.


;; see new stuff

(define is-static-class
  (lambda (name)
    (if (assq name the-static-class-env)
        #t
        #f)))

(define type-of
  (lambda (exp tenv)
    (cases expression exp

           (const-exp (num) (int-type))

           (var-exp (var) (apply-tenv tenv var))

           (diff-exp (exp1 exp2)
                     (let ((type1 (type-of exp1 tenv))
                           (type2 (type-of exp2 tenv)))
                       (check-equal-type! type1 (int-type) exp1)
                       (check-equal-type! type2 (int-type) exp2)
                       (int-type)))

           (sum-exp (exp1 exp2)
                    (let ((type1 (type-of exp1 tenv))
                          (type2 (type-of exp2 tenv)))
                      (check-equal-type! type1 (int-type) exp1)
                      (check-equal-type! type2 (int-type) exp2)
                      (int-type)))

           (zero?-exp (exp1)
                      (let ((type1 (type-of exp1 tenv)))
                        (check-equal-type! type1 (int-type) exp1)
                        (bool-type)))

           (if-exp (test-exp true-exp false-exp)
                   (let
                       ((test-type (type-of test-exp tenv))
                        (true-type (type-of true-exp tenv))
                        (false-type (type-of false-exp tenv)))
                     ;; these tests either succeed or raise an error
                     (check-equal-type! test-type (bool-type) test-exp)
                     (check-equal-type! true-type false-type exp)
                     true-type))

           (let-exp (ids rands body)
                    (let ((new-tenv
                           (extend-tenv
                            ids
                            (types-of-exps rands tenv)
                            tenv)))
                      (type-of body new-tenv)))

           (proc-exp (bvars bvar-types body)
                     (let ((result-type
                            (type-of body
                                     (extend-tenv bvars bvar-types tenv))))
                       (proc-type bvar-types result-type)))

           (call-exp (rator rands)
                     (let ((rator-type (type-of rator tenv))
                           (rand-types  (types-of-exps rands tenv)))
                       (type-of-call rator-type rand-types rands exp)))

           (letrec-exp (proc-result-types proc-names
                                          bvarss bvar-typess proc-bodies
                                          letrec-body)
                       (let ((tenv-for-letrec-body
                              (extend-tenv
                               proc-names
                               (map proc-type bvar-typess proc-result-types)
                               tenv)))
                         (for-each
                          (lambda (proc-result-type bvar-types bvars proc-body)
                            (let ((proc-body-type
                                   (type-of proc-body
                                            (extend-tenv
                                             bvars
                                             bvar-types
                                             tenv-for-letrec-body)))) ;; !!
                              (check-equal-type!
                               proc-body-type proc-result-type proc-body)))
                          proc-result-types bvar-typess bvarss proc-bodies)
                         (type-of letrec-body tenv-for-letrec-body)))

           (begin-exp (exp1 exps)
                      (letrec
                          ((type-of-begins
                            (lambda (e1 es)
                              (let ((v1 (type-of e1 tenv)))
                                (if (null? es)
                                    v1
                                    (type-of-begins (car es) (cdr es)))))))
                        (type-of-begins exp1 exps)))

           (assign-exp (id rhs)
                       (check-is-subtype!
                        (type-of rhs tenv)
                        (apply-tenv tenv id)
                        exp)
                       (void-type))

           (list-exp (exp1 exps)
                     (let ((type-of-car (type-of exp1 tenv)))
                       (for-each
                        (lambda (exp)
                          (check-equal-type!
                           (type-of exp tenv)
                           type-of-car
                           exp))
                        exps)
                       (list-type type-of-car)))

           ;; object stuff begins here
           (new-object-exp (class-name rands)
                           (let ((arg-types (types-of-exps rands tenv))
                                 (c (lookup-static-class class-name)))
                             (cases static-class c
                                    (an-interface (method-tenv)
                                                  (report-cant-instantiate-interface class-name))
                                    (a-static-class (super-name i-names
                                                                field-names field-types method-tenv)
                                                    ;; check the call to initialize
                                                    (type-of-call
                                                     (find-method-type
                                                      class-name
                                                      'initialize)
                                                     arg-types
                                                     rands
                                                     exp)
                                                    ;; and return the class name as a type
                                                    (class-type class-name)))))

           (self-exp ()
                     (apply-tenv tenv '%self))

           (method-call-exp (obj-exp method-name rands)
                            (let ((arg-types (types-of-exps rands tenv))
                                  (obj-type (type-of obj-exp tenv)))
                              (type-of-call
                               (find-method-type
                                (type->class-name obj-type)
                                method-name)
                               arg-types
                               rands
                               exp)))

           (super-call-exp (method-name rands)
                           (let ((arg-types (types-of-exps rands tenv))
                                 (obj-type (apply-tenv tenv '%self)))
                             (type-of-call
                              (find-method-type
                               (apply-tenv tenv '%super)
                               method-name)
                              arg-types
                              rands
                              exp)))

           ;;new stuff: obj-type is not a obj will report a error
           (cast-exp (exp class-name)
                     (let ((obj-type (type-of exp tenv)))
                       (if (is-static-class class-name)
                           (if (class-type? obj-type)
                               (class-type class-name)
                               (report-bad-type-to-cast obj-type exp))
                           (error "error cast: ~s is not a class\n" class-name))))


           ;; instanceof in interp.scm behaves the same way as cast:  it
           ;; calls object->class-name on its argument, so we need to
           ;; check that the argument is some kind of object, but we
           ;; don't need to look at class-name at all.
           (instanceof-exp (exp class-name)
                           (let ((obj-type (type-of exp tenv)))
                               (if (is-static-class class-name)
                                   (if (class-type? obj-type)
                                       (bool-type)
                                       (report-bad-type-to-instanceof obj-type exp))
                                   (error 'instanceof " ~s is not a class\n" class-name))))

           )))


;;  (check "class c1 extends object
;; method int initialize () 1
;; class c2 extends object
;; method int initialize () 2
;; let p = proc (o : c1) instanceof o c3 in 11")

;; => error, for c3 is not a class

;; (check "class c1 extends object
;; method int initialize ()1
;; method int get()2

;; class c2 extends c1
;; let f = proc (o : c2) send cast o c3 get() in (f new c2())")

;; => error , for c3 is not a class

(run-all)

(check-all)

;; case bad-instance-of-1 will got a error
