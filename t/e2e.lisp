;;;; t/e2e.lisp -- meet-dapla-deploy/e2e
;;;;
;;;; Post-deploy smoke tests for the Gathio stack. Run via
;;;; `./meet-dapla-deploy.ros e2e` against a live deployment.

(defpackage :meet-dapla-deploy/e2e
  (:use :cl :fiveam)
  (:import-from :meet-dapla-deploy/deploy :*haproxy-fqdn*)
  (:export :run-e2e))

(in-package :meet-dapla-deploy/e2e)

(def-suite :meet-dapla-deploy-e2e
  :description "Smoke tests for Gathio at meet.dapla.net.")

(in-suite :meet-dapla-deploy-e2e)

(defun base-url ()
  (format nil "https://~A" *haproxy-fqdn*))

(test http-redirect
  "Plain HTTP requests redirect to HTTPS."
  (multiple-value-bind (body status)
      (dex:get (format nil "http://~A/" *haproxy-fqdn*)
               :force-string t :want-stream nil :redirect nil)
    (declare (ignore body))
    (is (member status '(301 302)))))

(test frontend-responds
  "The Gathio frontend returns HTTP 200."
  (multiple-value-bind (body status)
      (dex:get (base-url) :force-string t :want-stream nil)
    (declare (ignore body))
    (is (= 200 status))))

(test ical-content-type
  "The /events endpoint serves iCal content when requested."
  (multiple-value-bind (body status headers)
      (dex:get (format nil "~A/events" (base-url))
               :force-string t :want-stream nil
               :headers '(("Accept" . "text/calendar")))
    (declare (ignore body))
    (is (= 200 status))
    (is (uiop:string-prefix-p "text/calendar"
                               (gethash "content-type" headers "")))))

(defun run-e2e ()
  "Run the post-deploy e2e suite and signal an error if any test fails."
  (let ((results (run :meet-dapla-deploy-e2e)))
    (unless (every #'fiveam::test-passed-p results)
      (error "meet-dapla-deploy e2e suite: one or more tests failed."))))
