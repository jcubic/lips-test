;;   __ __                          __
;;  / / \ \       _    _  ___  ___  \ \
;; | |   \ \     | |  | || . \/ __>  | |
;; | |    > \    | |_ | ||  _/\__ \  | |
;; | |   / ^ \   |___||_||_|  <___/  | |
;;  \_\ /_/ \_\                     /_/
;;
;; <https://lips.js.org>
;;
;; This file contain essential functions and macros for LIPS
;;
;; This file is part of the LIPS - Scheme based Powerful lisp in JavaScript
;; Copyright (C) 2019-2020 Jakub T. Jankiewicz <https://jcubic.pl>
;; Released under MIT license

;; -----------------------------------------------------------------------------
(define (%doc string fn)
  (typecheck "%doc" fn "function")
  (typecheck "%doc" string "string")
  (set-obj! fn '__doc__ (--> string (replace /^ +/mg "")))
  fn)

;; -----------------------------------------------------------------------------
(define-macro (let-syntax vars . body)
  "(let-syntax ((name fn)) body)

    Macro works like combination of let and define-syntax. It creaates
    local macros and evaluate body in context of those macros.
    The macro to letrec-syntax is like letrec is to let."
  `(let ,vars
     ,@(map (lambda (rule)
              `(typecheck "let-syntax" ,(car rule) "syntax"))
            vars)
     ,@body))

;; -----------------------------------------------------------------------------
(define-macro (letrec-syntax vars . body)
  "(letrec-syntax ((name fn)) body)

    Macro works like combination of letrec and define-syntax. It creaates
    local macros and evaluate body in context of those macros."
  `(letrec ,vars
     ,@(map (lambda (rule)
              `(typecheck "letrec-syntax" ,(car rule) "syntax"))
            vars)
     ,@body))

;; -----------------------------------------------------------------------------
(define-macro (define-syntax name expr . rest)
  "(define-syntax name expression [__doc__])

   Macro define new hygienic macro using syntax-rules with optional documentation"
  (let ((expr-name (gensym "expr-name")))
    `(define ,name
       (let ((,expr-name ,expr))
         (typecheck "define-syntax" ,expr-name "syntax")
         ,expr-name)
       ,@rest)))

;; -----------------------------------------------------------------------------
(define (quoted-symbol? x)
   "(quoted-symbol? code)

   Helper function that test if value is quoted symbol. To be used in macros
   that pass literal code that is transformed by parser.

   usage:

      (define-macro (test x)
         (if (quoted-symbol? x)
             `',(cadr x)))

      (list 'hello (test 'world))"
   (and (pair? x) (eq? (car x) 'quote) (symbol? (cadr x)) (null? (cddr x))))

;; -----------------------------------------------------------------------------
(define-macro (--> expr . code)
  "Helper macro that simplify calling methods on objects. It work with chaining

   usage: (--> ($ \"body\")
               (css \"color\" \"red\")
               (on \"click\" (lambda () (display \"click\"))))

          (--> document (querySelectorAll \"div\"))
          (--> (fetch \"https://jcubic.pl\")
               (text)
               (match /<title>([^<]+)<\\/title>/)
               1)
          (--> document
               (querySelectorAll \".cmd-prompt\")
               0
               \"innerText\")
          (--> document.body
               (style.setProperty \"--color\" \"red\"))"
  (let ((obj (gensym "obj")))
    `(let* ((,obj ,expr))
       ,@(map (lambda (code)
                (let ((value (gensym "value")))
                  `(let* ((,value ,(let ((name (cond ((quoted-symbol? code) (symbol->string (cadr code)))
                                                     ((pair? code) (symbol->string (car code)))
                                                     (true code))))
                                       (if (string? name)
                                           `(. ,obj ,@(split "." name))
                                           `(. ,obj ,name)))))
                     ,(if (and (pair? code) (not (quoted-symbol? code)))
                         `(set! ,obj (,value ,@(cdr code)))
                         `(set! ,obj ,value)))))
              code)
       ,obj)))

;; -----------------------------------------------------------------------------
(define-macro (define-global first . rest)
  "(define-global var value)
   (define-global (name . args) body)

   Macro that define functions or variables in global context, so they can be used
   inside let and get let variables in closure, Useful for universal macros."
  (if (pair? first)
      (let ((name (car first)))
        `(--> lips.env
              (set ,(symbol->string name) (lambda ,(cdr first) ,@rest))))
      `(--> lips.env (set ,(symbol->string first) ,(car rest)))))

;; -----------------------------------------------------------------------------
(define-macro (globalize expr . rest)
  "(globalize expr)

    Macro will get the value of the expression and add each method as function to global
    scope."
  (let* ((env (current-environment))
         (obj (eval expr env))
         (name (gensym "name"))
         (env-name (gensym "env-name"))
         (make-name (if (pair? rest)
                        (let ((pre (symbol->string (car rest))))
                          (lambda (name) (string->symbol (concat pre name))))
                        string->symbol)))
    `(let ((,name ,expr))
       ,@(filter pair?
                 (map (lambda (key)
                        (if (and (not (match /^_/ key)) (function? (. obj key)))
                            (let* ((args (gensym "args")))
                              `(define-global (,(make-name key) . ,args)
                                 (apply (. ,name ,key) ,args)))))
                        (array->list (--> Object (keys obj))))))))

;; -----------------------------------------------------------------------------
(define (single list)
  "(single list)

   Function check if argument is list with single element"
  (and (pair? list) (not (cdr list))))

;; -----------------------------------------------------------------------------
(define (iterator? x)
   "(iterator? x)

     Function check if value is JavaScript iterator object"
   (and (object? x) (procedure? (. x Symbol.iterator))))

;; -----------------------------------------------------------------------------
(define-macro (.. expr)
  "(.. foo.bar.baz)

   Macro that gets value from nested object where argument is comma separated symbol"
  (if (not (symbol? expr))
      expr
      (let ((parts (split "." (symbol->string expr))))
        (if (single parts)
            expr
            `(. ,(string->symbol (car parts)) ,@(cdr parts))))))

;; ---------------------------------------------------------------------------------------
(define (plain-object? x)
  "(plain-object? x)

   Function check if value is plain JavaScript object. Created using object macro."
  ;; here we don't use string=? or equal? because it may not be defined
  (and (== (--> (type x) (cmp "object")) 0) (eq? (. x 'constructor) Object)))

;; -----------------------------------------------------------------------------
(define (symbol->string s)
  "(symbol->string symbol)

   Function convert LIPS symbol to string."
  (if (symbol? s)
      (let ((name s.__name__))
        (if (string? name)
            name
            (--> name (toString))))))

;; -----------------------------------------------------------------------------
(define (string->symbol string)
  "(string->symbol string)

   Function convert string to LIPS symbol."
  (and (string? string) (%as.data (new (. lips "LSymbol") string))))

;; -----------------------------------------------------------------------------
(define (alist->object alist)
  "(alist->object alist)

   Function convert alist pairs to JavaScript object."
  (if (pair? alist)
      (alist.toObject)
      (alist->object (new lips.Pair undefined nil))))

;; -----------------------------------------------------------------------------
(define (parent.frames)
  "(parent.frames)

   Funcion return list of environments from parent frames (lambda function calls)"
  (let iter ((result '()) (frame (parent.frame 1)))
    (if (eq? frame (interaction-environment))
        (cons frame result)
        (if (null? frame)
            result
            (let ((parent.frame (--> frame (get 'parent.frame (object :throwError false)))))
              (if (function? parent.frame)
                  (iter (cons frame result) (parent.frame 0))
                  result))))))

;; -----------------------------------------------------------------------------
(define-macro (wait time . expr)
  "(wait time . expr)

   Function return promise that will resolve with evaluating the expression after delay."
  `(promise (timer ,time (resolve (begin ,@expr)))))

;; -----------------------------------------------------------------------------
(define (pair-map fn seq-list)
  "(pair-map fn list)

   Function call fn argument for pairs in a list and return combined list with
   values returned from function fn. It work like the map but take two items from list"
  (let iter ((seq-list seq-list) (result '()))
    (if (null? seq-list)
        result
        (if (and (pair? seq-list) (pair? (cdr seq-list)))
            (let* ((first (car seq-list))
                   (second (cadr seq-list))
                   (value (fn first second)))
              (if (null? value)
                  (iter (cddr seq-list) result)
                  (iter (cddr seq-list) (cons value result))))))))


;; -----------------------------------------------------------------------------
(define (object-expander readonly expr . rest)
  "(object-expander reaonly '(:foo (:bar 10) (:baz (1 2 3))))

   Recursive function helper for defining LIPS code for create objects
   using key like syntax."
  (let ((name (gensym "name")) (quot (if (null? rest) false (car rest))))
    (if (null? expr)
        `(alist->object ())
        `(let ((,name (alist->object '())))
           ,@(pair-map (lambda (key value)
                         (if (not (key? key))
                             (let ((msg (string-append (type key)
                                                       " "
                                                       (repr key)
                                                       " is not a symbol!")))
                               (throw msg))
                             (let ((prop (key->string key)))
                               (if (and (pair? value) (key? (car value)))
                                   `(set-obj! ,name
                                              ,prop
                                              ,(object-expander readonly value))
                                    (if quot
                                        `(set-obj! ,name ,prop ',value)
                                        `(set-obj! ,name ,prop ,value))))))
                       expr)
           ,(if readonly
               `(Object.freeze ,name))
           ,name))))

;; -----------------------------------------------------------------------------
(define-macro (object . expr)
  "(object :name value)

   Macro that create JavaScript object using key like syntax."
  (try
    (object-expander false expr)
    (catch (e)
      (error e.message))))

;; -----------------------------------------------------------------------------
(define-macro (object-literal . expr)
  "(object-literal :name value)

   Macro that create JavaScript object using key like syntax. This is similar,
   to object but all values are quoted. This macro is used with & object literal."
  (try
    (object-expander true expr)
    (catch (e)
      (error e.message))))

;; -----------------------------------------------------------------------------
(define (alist->assign desc . sources)
  "(alist->assign alist . list-of-alists)

   Function that work like Object.assign but for LIPS alist."
  (for-each (lambda (source)
              (for-each (lambda (pair)
                          (let* ((key (car pair))
                                 (value (cdr pair))
                                 (d-pair (assoc key desc)))
                            (if (pair? d-pair)
                                (set-cdr! d-pair value)
                                (append! desc (list pair)))))
                        source))
            sources)
  desc)

;; -----------------------------------------------------------------------------
(define (key? symbol)
  "(key? symbol)

   Function check if symbol is key symbol, have colon as first character."
  ;; we can't use string=? because it's in R5RS.scm we use same code that use cmp
  (and (symbol? symbol) (== (--> (substring (symbol->string symbol) 0 1) (cmp ":")) 0)))

;; -----------------------------------------------------------------------------
(define (key->string symbol)
  "(key->string symbol)

   If symbol is key it convert that to string - remove colon."
  (if (key? symbol)
      (substring (symbol->string symbol) 1)))

;; -----------------------------------------------------------------------------
(define (%as.data obj)
  "(%as.data obj)

   Mark object as data to stop evaluation."
  (if (object? obj)
      (begin
        (set-obj! obj 'data true)
        obj)))

;; -----------------------------------------------------------------------------
(define (dir obj)
  "(dir obj)

   Function return all props on the object including those in prototype chain."
  (if (or (null? obj) (eq? obj Object.prototype))
      nil
      (let ((names (Object.getOwnPropertyNames obj))
            (proto (Object.getPrototypeOf obj)))
        (append (array->list names) (dir proto)))))


;; ---------------------------------------------------------------------------------------
(define (tree-map f tree)
  "(tree-map fn tree)

   Tree version of map. Function is invoked on every leaf."
  (if (pair? tree)
      (cons (tree-map f (car tree)) (tree-map f (cdr tree)))
      (f tree)))

;; -----------------------------------------------------------------------------
(define (native.number x)
  "(native.number obj)

   If argument is number it will convert to native number."
  (if (number? x)
      (value x)
      x))

;; -----------------------------------------------------------------------------
(define (value obj)
  "(value obj)

   Function unwrap LNumbers and convert nil value to undefined."
  (if (eq? obj nil)
      undefined
      (if (number? obj)
          ((. obj "valueOf"))
          obj)))

;; -----------------------------------------------------------------------------
(define-macro (define-formatter-rule . patterns)
  "(rule-pattern pattern)

   Anaphoric Macro for defining patterns for formatter. With Ahead, Pattern and * defined values."
  (let ((rules (gensym "rules")))
    `(let ((,rules lips.Formatter.rules)
           (Ahead (lambda (pattern)
                    (let ((Ahead (.. lips.Formatter.Ahead)))
                      (new Ahead (if (string? pattern) (new RegExp pattern) pattern)))))
           (* (Symbol.for "*"))
           (Pattern (lambda (pattern flag)
                      (new lips.Formatter.Pattern (list->array pattern)
                           (if (null? flag) undefined flag)))))
       ,@(map (lambda (pattern)
                `(--> ,rules (push (tree->array (tree-map native.number ,@pattern)))))
              patterns))))


;; -----------------------------------------------------------------------------
;; macro code taken from https://stackoverflow.com/a/27507779/387194
;; which is based on https://srfi.schemers.org/srfi-61/srfi-61.html
;; but with lowercase tokens
;; NOTE: this code make everything really slow
;;       unit tests run from 1min to 6min.
;; TODO: test this when syntax macros are compiled before evaluation
;; -----------------------------------------------------------------------------
(define-syntax cond
  (syntax-rules (=> else)

    ((cond (else else1 else2 ...))
     ;; The (if #t (begin ...)) wrapper ensures that there may be no
     ;; internal definitions in the body of the clause.  R5RS mandates
     ;; this in text (by referring to each subform of the clauses as
     ;; <expression>) but not in its reference implementation of cond,
     ;; which just expands to (begin ...) with no (if #t ...) wrapper.
     (if #t (begin else1 else2 ...)))

    ((cond (test => receiver) more-clause ...)
     (let ((t test))
       (cond/maybe-more t
                        (receiver t)
                        more-clause ...)))

    ((cond (generator guard => receiver) more-clause ...)
     (call-with-values (lambda () generator)
       (lambda t
         (cond/maybe-more (apply guard    t)
                          (apply receiver t)
                          more-clause ...))))

    ((cond (test) more-clause ...)
     (let ((t test))
       (cond/maybe-more t t more-clause ...)))

    ((cond (test body1 body2 ...) more-clause ...)
     (cond/maybe-more test
                      (begin body1 body2 ...)
                      more-clause ...)))
  "(cond (predicate? . body)
         (predicate? . body)
         (else . body))

   Macro for condition checks. For usage instead of nested ifs.")

;; -----------------------------------------------------------------------------
(define-syntax cond/maybe-more
  (syntax-rules ()
    ((cond/maybe-more test consequent)
     (if test
         consequent))
    ((cond/maybe-more test consequent clause ...)
     (if test
         consequent
         (cond clause ...))))
  "(cond/maybe-more test consequent ...)

   Helper macro used by cond.")


(define-macro (cond . list)
  "(cond (predicate? . body)
         (predicate? . body))
   Macro for condition check. For usage instead of nested ifs."
  (if (pair? list)
      (let* ((item (car list))
             (first (car item))
             (forms (cdr item))
             (rest (cdr list)))
        `(if ,first
             (begin
               ,@forms)
             ,(if (and (pair? rest)
                       (or (eq? (caar rest) true)
                           (eq? (caar rest) 'else)))
                  `(begin
                     ,@(cdar rest))
                  (if (not (null? rest))
                      `(cond ,@rest)))))
      nil))


;; -----------------------------------------------------------------------------
;; formatter rules for cond to break after each S-Expression
;; regex literal /[^)]/ breaks scheme emacs mode so we use string and macro
;; use RegExp constructor
;; -----------------------------------------------------------------------------
(define (%r re . rest)
  "(%r re)

   Create new regular expression from string, to not break Emacs formatting"
   (if (null? rest)
     (new RegExp re)
     (new RegExp re (car rest))))

;; -----------------------------------------------------------------------------
;; replaced by more general formatter in JS, this is left as example of usage
;; -----------------------------------------------------------------------------
#;(define-formatter-rule ((list (list "("
                                    (%r "(?:#:)?cond")
                                    (Pattern (list "(" * ")") "+"))
                               1
                               (Ahead "[^)]"))))

;; -----------------------------------------------------------------------------
(define (interaction-environment)
  "(interaction-environment)

   Function return interaction environement equal to lips.env can be overwritten,
   when creating new interpreter with lips.Interpreter."
  **interaction-environment**)

;; -----------------------------------------------------------------------------
(define (current-output-port)
  "(current-output-port)

   Function return default stdout port."
  (let-env (interaction-environment)
     stdout))

;; -----------------------------------------------------------------------------
(define (current-error-port)
  "(current-output-port)

   Function return default stdout port."
  (let-env (interaction-environment)
     stderr))

;; -----------------------------------------------------------------------------
(define (current-input-port)
  "current-input-port)

   Function return default stdin port."
  (let-env (interaction-environment)
     stdin))

;; -----------------------------------------------------------------------------
(define (regex? x)
  "(regex? x)

   Function return true of value is regular expression, it return false otherwise."
  (== (--> (type x) (cmp "regex")) 0))

;; -----------------------------------------------------------------------------
(define (set-repr! type fn)
  "(add-repr! type fn)

   Function add string represention to the type, which should be constructor function.

   Function fn should have args (obj q) and it should return string, obj is vlaue that
   need to be converted to string, if the object is nested and you need to use `repr`,
   it should pass second parameter q to repr, so string will be quoted when it's true.

   e.g.: (lambda (obj q) (string-append \"<\" (repr obj q) \">\"))"
  (typecheck "add-repr!" type "function")
  (typecheck "add-repr!" fn "function")
  (ignore (--> lips.repr (set type fn))))

;; -----------------------------------------------------------------------------
(define (unset-repr! type)
  "(unset-repr! type)

   Function remove string represention to the type, which should be constructor function,
   added by add-repr! function."
  (typecheck "unset-repr!" type "function")
  (ignore (--> lips.repr (delete type))))

;; -----------------------------------------------------------------------------
;; add syntax &(:foo 10) that evaluates (object :foo 10)
;; -----------------------------------------------------------------------------
(set-special! "&" 'object-literal lips.specials.SPLICE)
;; -----------------------------------------------------------------------------
(set-repr! Object
           (lambda (x q)
             (concat "&("
                     (--> (Object.getOwnPropertyNames x)
                          (map (lambda (key)
                                 (concat ":" key
                                         " "
                                         (repr (. x key) q))))
                          (join " "))
                     ")")))

;; -----------------------------------------------------------------------------
(define (bound? x . rest)
  "(bound? x [env])

   Function check if variable is defined in given environement or interaction environment
   if not specified."
  (let ((env (if (null? rest) (interaction-environment) (car rest))))
    (try (begin
           (--> env (get x))
           true)
         (catch (e)
                false))))

;; -----------------------------------------------------------------------------
(define (environment-bound? env x)
  "(environment-bound? env symbol)

   Function check if symbol is bound variable similar to bound?."
  (typecheck "environment-bound?" env "environment" 1)
  (typecheck "environment-bound?" x "symbol" 2)
  (bound? x env))

;; -----------------------------------------------------------------------------
;; source https://stackoverflow.com/a/4297432/387194
;; -----------------------------------------------------------------------------
(define (qsort e predicate)
  "(qsort list predicate)

   Sort the list using quick sort alorithm according to predicate."
  (if (or (null? e) (<= (length e) 1))
      e
      (let loop ((left nil) (right nil)
                 (pivot (car e)) (rest (cdr e)))
        (if (null? rest)
            (append (append (qsort left predicate) (list pivot)) (qsort right predicate))
            (if (predicate (car rest) pivot)
                (loop (append left (list (car rest))) right pivot (cdr rest))
                (loop left (append right (list (car rest))) pivot (cdr rest)))))))

;; -----------------------------------------------------------------------------
(define (sort list . rest)
  "(sort list [predicate])

   Sort the list using optional predicate function. if not function is specified
   it will use <= and sort in increasing order."
  (let ((predicate (if (null? rest) <= (car rest))))
    (typecheck "sort" list "pair")
    (typecheck "sort" predicate "function")
    (qsort list predicate)))

;; -----------------------------------------------------------------------------
(define (every fn list)
  "(every fn list)

   Function call function fn on each item of the list, if every value is true
   it will return true otherwise it return false."
  (if (null? list)
      true
      (and (fn (car list)) (every fn (cdr list)))))

;; -----------------------------------------------------------------------------
(define (zip . args)
  "(zip list1 list2 ...)

   Create one list by taking each element of each list."
  (if (null? args)
      nil
      (if (some null? args)
         nil
         (cons (map car args) (apply zip (map cdr args))))))

;; ---------------------------------------------------------------------------------------
(define-macro (promise . body)
  "(promise . body)

   Anaphoric macro that expose resolve and reject functions from JS promise"
  `(new Promise (lambda (resolve reject)
                  (try (begin ,@body)
                       (catch (e)
                              (error (.. e.message)))))))

;; ---------------------------------------------------------------------------------------
(define-macro (timer time . body)
  "(timer time . body)

   Macro evaluate expression after delay, it return timer. To clear the timer you can use
   native JS clearTimeout function."
  `(setTimeout (lambda () (try (begin ,@body) (catch (e) (error (.. e.message))))) ,time))

;; ---------------------------------------------------------------------------------------
(define (defmacro? obj)
  "(defmacro? expression)

   Function check if object is macro and it's expandable."
  (and (macro? obj) (. obj 'defmacro)))

;; ---------------------------------------------------------------------------------------
(define (n-ary n fn)
  "(n-ary n fn)

   Return new function that limit number of arguments to n."
  (lambda args
    (apply fn (take n args))))

;; ---------------------------------------------------------------------------------------
(define (take n lst)
  "(take n list)

   Return n first values of the list."
  (let iter ((result '()) (i n) (lst lst))
    (if (or (null? lst) (<= i 0))
        (reverse result)
        (iter (cons (car lst) result) (- i 1) (cdr lst)))))

;; ---------------------------------------------------------------------------------------
(define unary (%doc "(unary fn)

                     Function return new function with arguments limited to one."
                    (curry n-ary 1)))

;; ---------------------------------------------------------------------------------------
(define binary (%doc "(binary fn)

                      Function return new function with arguments limited to two."
                      (curry n-ary 2)))

;; ---------------------------------------------------------------------------------------
;; LIPS Object System
;; ---------------------------------------------------------------------------------------

(define (%class-lambda expr)
  "(class-lambda expr)

   Return lambda expression where input expression lambda have `this` as first argument."
  (let ((args (gensym 'args)))
    `(lambda ,args
       (apply ,(cadr expr) this ,args))))

;; TODO: handle this broken case when arguments are improper list
;;       Throw proper error
;; (%class-lambda '(hello (lambda (x y . z) (print z))))

(define (%class-lambda expr)
  "(%class-lambda expr)

  Define lambda that have self is first argument. The expr is in a form:
  (constructor (lambda (self ...) . body)) as given by define-class macro."
  (let ((args (cdadadr expr)))
    `(lambda (,@args)
       (,(cadr expr) this ,@args))))

;; ---------------------------------------------------------------------------------------
(define (%class-method-name expr)
  "(%class-method-name expr)

   Helper function that allow to use [Symbol.asyncIterator] inside method name."
  (if (pair? expr)
      (car expr)
      (list 'quote expr)))

;; ---------------------------------------------------------------------------------------
(define-macro (define-class name parent . body)
  "(define-class name parent . body)

   Define class - JavaScript function constructor with prototype.

   usage:

     (define-class Person Object
         (constructor (lambda (self name)
                        (set-obj! self '_name name)))
         (hi (lambda (self)
               (display (string-append self._name \" say hi\"))
               (newline))))
     (define jack (new Person \"Jack\"))
     (jack.hi)"
  (let iter ((functions '()) (constructor '()) (lst body))
    (if (null? lst)
        `(begin
           (define ,name ,(if (null? constructor)
                              `(lambda ())
                              (%class-lambda constructor)))
           (set-obj! ,name (Symbol.for "__class__") true)
           ,(if (and (not (null? parent)) (not (eq? parent 'Object)))
                `(begin
                   (set-obj! ,name 'prototype (Object.create (. ,parent 'prototype)))
                   (set-obj! (. ,name 'prototype) 'constructor ,name)))
           ,@(map (lambda (fn)
                    `(set-obj! (. ,name 'prototype)
                               ,(%class-method-name (car fn))
                               ,(%class-lambda fn)))
                  functions))
        (let ((item (car lst)))
          (if (eq? (car item) 'constructor)
              (iter functions item (cdr lst))
              (iter (cons item functions) constructor (cdr lst)))))))

;; ---------------------------------------------------------------------------------------
(define-syntax class
  (syntax-rules ()
    ((_)
     (error "class: parent required"))
    ((_ parent body ...)
     (let ()
       (define-class temp parent body ...)
       temp)))
  "(class <parent> body ...)

   Macro allow to create anonymous classes. See define-class for details.")

;; ---------------------------------------------------------------------------------------
(define (make-tags expr)
  "(make-tags expression)

   Function that return list structure of code with better syntax then raw LIPS"
  `(h ,(let ((val (car expr))) (if (key? val) (key->string val) val))
      (alist->object (,'quasiquote ,(pair-map (lambda (car cdr)
                                                `(,(key->string car) . (,'unquote ,cdr)))
                                              (cadr expr))))
      ,(if (not (null? (cddr expr)))
           (if (and (pair? (caddr expr)) (let ((s (caaddr expr)))
                                           (and (symbol? s) (eq? s 'list))))
               `(list->array (list ,@(map make-tags (cdaddr expr))))
               (caddr expr)))))

;; ---------------------------------------------------------------------------------------
(define (%sxml h expr)
  "(%sxml h expr)

   Helper function that render expression using create element function."
  (let* ((have-attrs (and (not (null? (cdr expr)))
                          (pair? (cadr expr))
                          (eq? (caadr expr) '@)))
         (attrs (if have-attrs
                    (cdadr expr)
                    nil))
         (rest (if have-attrs
                   (cddr expr)
                   (cdr expr))))
    `(,h ,(let* ((symbol (car expr))
                 (name (symbol->string symbol)))
            (if (char-lower-case? (car (string->list name)))
                name
                symbol))
         (alist->object (,'quasiquote ,(map (lambda (pair)
                                             (cons (symbol->string (car pair))
                                                   (list 'unquote (cadr pair))))
                                           attrs)))
         ,@(if (null? rest)
              nil
              (let ((first (car rest)))
                (if (pair? first)
                    (map (lambda (expr)
                           (%sxml h expr))
                         rest)
                    (list first)))))))

;; ---------------------------------------------------------------------------------------
(define-macro (sxml expr)
  "(sxml expr)

   Macro for JSX like syntax but with SXML.
   e.g. usage:

   (sxml (div (@ (data-foo \"hello\")
                 (id \"foo\"))
              (span \"hello\")
              (span \"world\")))"
  (%sxml 'h expr))

;; ---------------------------------------------------------------------------------------
(define-macro (with-tags expr)
  "(with-tags expression)

   Macro that evalute LIPS shorter code for S-Expression equivalent of JSX.
   e.g.:

   (with-tags (:div (:class \"item\" :id \"item-1\")
                    (list (:span () \"Random Item\")
                          (:a (:onclick (lambda (e) (alert \"close\")))
                              \"close\"))))

   Above expression can be passed to function that renders JSX (like render in React, Preact)
   To get the string from the macro you can use vhtml library from npm."
  (make-tags expr))

;; ---------------------------------------------------------------------------------------
(define (get-script url)
  "(get-script url)

   Load JavaScript file in browser by adding script tag to head of the current document."
  (if (not (bound? 'document))
      (throw (new Error "get-script: document not defined"))
      (let ((script (document.createElement "script")))
        (new Promise (lambda (resolve reject)
                        (set-obj! script 'src url)
                        (set-obj! script 'onload (lambda ()
                                                   (resolve)))
                        (set-obj! script 'onerror (lambda ()
                                                    (reject "get-script: Failed to load")))
                        (if document.head
                            (document.head.appendChild script)))))))

;; ---------------------------------------------------------------------------------------
(define (gensym? value)
  "(gensym? value)

   Function return #t if value is symbol and it's gensym. It returns #f otherwise."
  (and (symbol? value) (--> value (is_gensym))))

;; ---------------------------------------------------------------------------------------
(define (degree->radians x)
  "(degree->radians x)

   Convert degree to radians."
  (* x (/ Math.PI 180)))

;; ---------------------------------------------------------------------------------------
(define (radians->degree x)
  "(radians->degree x)

   Convert radians to degree."
  (* x (/ 180 Math.PI)))

;; ---------------------------------------------------------------------------------------
(define-syntax while
  (syntax-rules ()
    ((_ predicate body ...)
     (do ()
       ((not predicate))
       body ...)))
  "(while cond . body)

   Macro that create a loop, it exectue body until cond expression is false.")

;; ---------------------------------------------------------------------------------------
(define-syntax ++
  (syntax-rules ()
    ((++ x)
     (let ((tmp (+ x 1)))
       (set! x tmp)
       tmp)))
  "(++ variable)

   Macro that work only on variables and increment the value by one.")

;; ---------------------------------------------------------------------------------------
(define-syntax --
  (syntax-rules ()
    ((-- x)
     (let ((tmp (- x 1)))
       (set! x tmp)
       tmp)))
  "(-- variable)

   Macro that decrement the value it work only on symbols")

;; ---------------------------------------------------------------------------------------
(define (pretty-format pair)
  "(pretty-format pair)

   Function return pretty printed string from pair expression."
  (typecheck "pretty-pair" pair "pair")
  (--> (new lips.Formatter (repr pair true)) (break) (format)))

;; ---------------------------------------------------------------------------------------
(define (reset)
  "(reset)

  Function reset environment and remove all user defined variables."
  (let-env **interaction-environment**
           (let ((defaults **interaction-environment-defaults**)
                 (env **interaction-environment**))
             (--> env (list) (forEach (lambda (name)
                                        (if (not (--> defaults (includes name)))
                                            (--> env (unset name)))))))))

;; ---------------------------------------------------------------------------------------
(define (make-list n . rest)
  (if (or (not (integer? n)) (<= n 0))
      (throw (new Error "make-list: first argument need to be integer larger then 0"))
      (let ((fill (if (null? rest) undefined (car rest))))
        (array->list (--> (new Array n) (fill fill))))))

;; ---------------------------------------------------------------------------------------
(define (range n)
  "(range n)

   Function return list of n numbers from 0 to n - 1"
  (typecheck "range" n "number")
  (array->list (--> (new Array n) (fill 0) (map (lambda (_ i) i)))))

;; ---------------------------------------------------------------------------------------
(define-macro (do-iterator spec cond . body)
  "(do-iterator (var expr) (test) body ...)

   Macro iterate over iterators (e.g. create with JavaScript generator function)
   it works with normal and async iterators. You can loop over infinite iterators
   and break the loop if you want, using expression like in do macro, long sync iterators
   will block main thread (you can't print 1000 numbers from inf iterators,
   because it will freeze the browser), but if you use async iterators you can process
   the values as they are generated."
  (let ((gen (gensym "name"))
        (name (car spec))
        (async (gensym "async"))
        (sync (gensym "sync"))
        (iterator (gensym "iterator"))
        (test (if (null? cond) #f (car cond)))
        (next (gensym "next"))
        (stop (gensym "stop"))
        (item (gensym "item")))
    `(let* ((,gen ,(cadr spec))
            (,sync (. ,gen Symbol.iterator))
            (,async (. ,gen Symbol.asyncIterator))
            (,iterator)
            (,next (lambda ()
                     ((. ,iterator "next")))))
          (if (or (procedure? ,sync) (procedure? ,async))
              (begin
                 (set! ,iterator (if (procedure? ,sync) (,sync) (,async)))
                 (let* ((,item (,next))
                        (,stop #f)
                        (,name (. ,item "value")))
                   (while (not (or (eq? (. ,item "done") #t) ,stop))
                      (if ,test
                           (set! ,stop #t)
                           (begin
                              ,@body))
                      (set! ,item (,next))
                      (set! ,name (. ,item "value")))))))))

;; ---------------------------------------------------------------------------------------
(set-repr! Set (lambda () "#<Set>"))
(set-repr! Map (lambda () "#<Met>"))

;; ---------------------------------------------------------------------------------------
(define (native-symbol? x)
  "(native-symbol? object)

   Function check if value is JavaScript symbol."
  (and (string=? (type x) "symbol") (not (symbol? x))))

;; ---------------------------------------------------------------------------------------
(set-special! "’" 'warn-quote)

;; ---------------------------------------------------------------------------------------
(define-macro (warn-quote)
  (throw (new Error (string-append "You're using invalid quote character run: "
                                   "(set-special! \"’\" 'quote)"
                                   " to allow running this type of quote"))))
