;; -*- scheme -*-
;; This is example hyperapp application written in LIPS
;;
;; This file is part of the LIPS - Scheme implementation in JavaScript
;; Copyriht (C) 2019-2020 Jakub T. Jankiewicz <https://jcubic.pl>
;; Released under MIT license
;;

(define h (.. hyperapp.h))
(define app (.. hyperapp.app))

;; helper for this specific app - hyperapp action generator that create new state

(define (update fn)
  "(update fn)

   Function create new action that create new state with updated alist value
   that is returned from function."
  (lambda (value)
    (lambda (state)
      (let* ((alist (. state "counter"))
             (old (cdr (assoc 'count alist))))
        (make-object :counter (alist->assign '() alist `((count . ,(fn old value)))))))))


;; -----------------------------------------------------------------------------
;; MAIN APPLICATION CODE
;; -----------------------------------------------------------------------------

;; Hyper app actions
(define actions (make-object :up (update +)
                             :down (update -)))


;; inital state
(define state (make-object :counter '((count . 0))))

(define (Counter obj)
  (with-tags (:h1 () (concat "Counter: " (. obj 'count)))))

(define (view state actions)
  "hyperapp view"
  (let ((counter (. state "counter")))
    (with-tags (:div ()
                     (list (Counter (:count (cdr (assoc 'count counter))))
                           (:button (:onclick (lambda () (--> actions (down 1)))) "-")
                           (:button (:onclick (lambda () (--> actions (up 1)))) "+"))))))

;; main hyper app
(define main (app state actions view (--> document (querySelector "#app"))))
