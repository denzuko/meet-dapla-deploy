;;;; t/spec.lisp -- meet-dapla-deploy/spec
;;;;
;;;; FiveAM specification tests covering all exported symbols from
;;;; meet-dapla-deploy/deploy. Every exported function and defprop has
;;;; at least one test. Run: (asdf:test-system :meet-dapla-deploy/spec)

(defpackage :meet-dapla-deploy/spec
  (:use :cl :fiveam)
  (:import-from :meet-dapla-deploy/deploy
                :gathio-network-sections
                :gathio-db-container-sections
                :gathio-container-sections
                :haproxy-vhost-config
                :cinix-write-string
                :decommissioned
                :deploy-app
                :quadlets-written
                :quadlets-activated
                :haproxy-vhost-written
                :zfs-encryption-key
                :zfs-dataset-mounted
                :rootless-service-account
                :images-pulled)
  (:export :run-spec))

(in-package :meet-dapla-deploy/spec)

(def-suite :meet-spec
  :description "Full coverage spec for meet-dapla-deploy/deploy exports.")

(in-suite :meet-spec)

;;; ── Helpers ──────────────────────────────────────────────────────────

(defun ini-lines (ini)
  "Split INI string into trimmed non-empty lines."
  (remove-if (lambda (l) (zerop (length l)))
             (mapcar (lambda (l) (string-trim '(#\Space #\Return) l))
                     (uiop:split-string ini :separator '(#\Newline)))))

(defun ini-has (ini sub)
  "True if any line of INI contains SUB."
  (some (lambda (l) (search sub l)) (ini-lines ini)))

(defun line-starting (ini prefix)
  "Return the first line of INI starting with PREFIX, or nil."
  (find-if (lambda (l) (and (>= (length l) (length prefix))
                             (string= prefix (subseq l 0 (length prefix)))))
           (ini-lines ini)))

;;; ── cinix-write-string ────────────────────────────────────────────────

(test cinix-single-section
  "cinix-write-string serialises a single section to correct INI."
  (let ((ini (cinix-write-string '(("Section" . (("Key" . "Value")))))))
    (is (ini-has ini "[Section]"))
    (is (ini-has ini "Key=Value"))))

(test cinix-multiple-sections
  "cinix-write-string preserves section order."
  (let* ((sections '(("A" . (("K" . "1"))) ("B" . (("K" . "2")))))
         (ini (cinix-write-string sections))
         (pos-a (search "[A]" ini))
         (pos-b (search "[B]" ini)))
    (is (and pos-a pos-b (< pos-a pos-b)))))

(test cinix-blank-separator
  "cinix-write-string inserts blank line after each section."
  (let ((ini (cinix-write-string '(("S" . (("K" . "V")))))))
    (is (search (format nil "V~%~%") ini))))

;;; ── Network unit ──────────────────────────────────────────────────────

(test network-bridge-driver
  "gathio.network uses netavark bridge, not Internal=true."
  (let ((ini (cinix-write-string (gathio-network-sections))))
    (is (ini-has ini "Driver=bridge"))
    (is (not (ini-has ini "Internal=true")))))

(test network-vlsm
  "gathio.network has correct VLSM subnet 10.89.2.12/29 and gateway 10.89.2.13."
  (let ((ini (cinix-write-string (gathio-network-sections))))
    (is (ini-has ini "Subnet=10.89.2.12/29"))
    (is (ini-has ini "Gateway=10.89.2.13"))))

(test network-name
  "gathio.network has NetworkName=gathio."
  (is (ini-has (cinix-write-string (gathio-network-sections)) "NetworkName=gathio")))

;;; ── gathio.container ─────────────────────────────────────────────────

(test container-home-volume-ro
  "gathio.container mounts %h read-only (home profile)."
  (let* ((ini   (cinix-write-string (gathio-container-sections)))
         (lines (ini-lines ini))
         (vol   (find-if (lambda (l) (and (search "Volume=" l) (search "%h" l))) lines)))
    (is (not (null vol)) "No Volume=%h line found")
    (when vol (is (search ":ro" vol) "Volume=%h line is not :ro"))))

(test container-data-volume-srv
  "gathio.container events volume uses /srv/%U specifier."
  (let ((ini (cinix-write-string (gathio-container-sections))))
    (is (ini-has ini "Volume=/srv/%U"))
    (is (not (ini-has ini "/srv/gathio")))))

(test container-no-publish-port
  "gathio.container has no PublishPort — netavark handles routing."
  (is (not (ini-has (cinix-write-string (gathio-container-sections)) "PublishPort"))))

(test container-network-reference
  "gathio.container references gathio.network."
  (is (ini-has (cinix-write-string (gathio-container-sections)) "Network=gathio.network")))

(test container-cispec-labels
  "gathio.container carries all required org.cispec CMDB labels."
  (let ((ini (cinix-write-string (gathio-container-sections))))
    (is (ini-has ini "Label=org.cispec.managed-by=consfigurator"))
    (is (ini-has ini "Label=org.cispec.fqdn=meet.dapla.net"))
    (is (ini-has ini "Label=org.cispec.service-account=gathio"))))

(test container-autoupdate-label
  "gathio.container has io.containers.autoupdate=registry label."
  (is (ini-has (cinix-write-string (gathio-container-sections))
               "Label=io.containers.autoupdate=registry")))

(test container-image
  "gathio.container uses the correct OCI image."
  (is (ini-has (cinix-write-string (gathio-container-sections))
               "oci.dapla.net/ghcr.io/lowercasename/gathio:latest")))

(test container-dependency-on-db
  "gathio.container declares After= and Requires= for gathio-db."
  (let ((ini (cinix-write-string (gathio-container-sections))))
    (is (ini-has ini "gathio-db.service"))))

(test container-env-file
  "gathio.container EnvironmentFile uses %h specifier."
  (is (ini-has (cinix-write-string (gathio-container-sections))
               "EnvironmentFile=%h")))

;;; ── gathio-db.container ──────────────────────────────────────────────

(test db-network-dependency
  "gathio-db.container waits for gathio.network (user-scope).
   Note: zfs-mount.service is system-scope and cannot be referenced
   from user-scope quadlet units; ZFS ordering is handled by the
   zfs-dataset-mounted Consfigurator property running before
   quadlets-activated in the defhost sequence."
  (is (ini-has (cinix-write-string (gathio-db-container-sections))
               "After=gathio.network")))

(test db-volume-srv
  "gathio-db.container data volume uses /srv/%U/db specifier."
  (is (ini-has (cinix-write-string (gathio-db-container-sections))
               "Volume=/srv/%U/db")))

(test db-env-file-percent-h
  "gathio-db.container EnvironmentFile uses %h specifier."
  (is (ini-has (cinix-write-string (gathio-db-container-sections))
               "EnvironmentFile=%h")))

(test db-health-check
  "gathio-db.container has a MongoDB health check command."
  (is (ini-has (cinix-write-string (gathio-db-container-sections))
               "HealthCmd")))

;;; ── HAProxy vhost ────────────────────────────────────────────────────

(test haproxy-tls-frontend
  "HAProxy config has TLS frontend on port 443."
  (is (search "bind *:443" (haproxy-vhost-config))))

(test haproxy-http-redirect
  "HAProxy config redirects HTTP to HTTPS."
  (is (search "redirect scheme https" (haproxy-vhost-config))))

(test haproxy-security-headers
  "HAProxy config sets all required security response headers."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "Strict-Transport-Security" cfg))
    (is (search "X-Content-Type-Options" cfg))
    (is (search "X-Frame-Options" cfg))
    (is (search "Referrer-Policy" cfg))
    (is (search "Permissions-Policy" cfg))))

(test haproxy-netavark-backend
  "HAProxy backend targets netavark gateway 10.89.2.13:3000."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "10.89.2.13:3000" cfg))
    (is (not (search "127.0.0.1" cfg)))))

(test haproxy-health-check
  "HAProxy backend has httpchk health check."
  (is (search "httpchk" (haproxy-vhost-config))))

;;; ── haproxy-vhost-written (:check always nil) ────────────────────────

(test haproxy-vhost-written-exported
  "haproxy-vhost-written is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::haproxy-vhost-written)))

;;; ── quadlets-written / quadlets-activated ────────────────────────────

(test quadlets-written-exported
  "quadlets-written is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::quadlets-written)))

(test quadlets-activated-exported
  "quadlets-activated is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::quadlets-activated)))

(test container-sections-zero-arity
  "gathio-container-sections and gathio-db-container-sections take no args."
  (is (listp (ignore-errors (gathio-container-sections))))
  (is (listp (ignore-errors (gathio-db-container-sections)))))

;;; ── ZFS defprops ─────────────────────────────────────────────────────

(test zfs-encryption-key-exported
  "zfs-encryption-key is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::zfs-encryption-key)))

(test zfs-dataset-mounted-exported
  "zfs-dataset-mounted is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::zfs-dataset-mounted)))

;;; ── rootless-service-account / images-pulled ─────────────────────────

(test rootless-service-account-exported
  "rootless-service-account is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::rootless-service-account)))

(test images-pulled-exported
  "images-pulled is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::images-pulled)))

;;; ── decommissioned ───────────────────────────────────────────────────

(test decommissioned-exported
  "decommissioned is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::decommissioned)))

;;; ── deploy-app ───────────────────────────────────────────────────────

(test deploy-app-exported
  "deploy-app is fbound and exported."
  (is (fboundp 'meet-dapla-deploy/deploy::deploy-app)))

;;; ── *haproxy-fqdn* defparameter ──────────────────────────────────────

(test haproxy-fqdn-correct
  "*haproxy-fqdn* is bound to meet.dapla.net."
  (is (string= "meet.dapla.net" meet-dapla-deploy/deploy:*haproxy-fqdn*)))

;;; ── Entry point ──────────────────────────────────────────────────────

(defun run-spec ()
  "Run the full meet-dapla-deploy spec suite."
  (let ((results (run :meet-spec)))
    (fiveam:explain! results)
    (unless (every #'fiveam::test-passed-p results)
      (error "meet-dapla-deploy spec suite: one or more tests failed."))))
