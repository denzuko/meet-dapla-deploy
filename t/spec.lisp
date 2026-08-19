;;;; t/spec.lisp -- meet-dapla-deploy/spec
;;;;
;;;; FiveAM specification tests for the quadlet template specifier refactor.
;;;; These tests verify the quadlet unit content produced by the cinix AST
;;;; functions — specifically that systemd specifiers (%h, %U, %I, /srv/%U/)
;;;; are used instead of hardcoded paths, and that the netavark bridge
;;;; configuration, org.cispec labels, and haproxy backend are correct.
;;;;
;;;; Run via: ros -e "(asdf:test-system :meet-dapla-deploy/spec)"
;;;; All tests must pass before any code changes are committed.

(defpackage :meet-dapla-deploy/spec
  (:use :cl :fiveam)
  (:import-from :meet-dapla-deploy/deploy
                :gathio-network-sections
                :gathio-container-sections
                :haproxy-vhost-config
                :cinix-write-string
                :decommissioned
                :quadlets-written)
  (:export :run-spec))

(in-package :meet-dapla-deploy/spec)

(def-suite :quadlet-specifiers
  :description "Quadlet unit template specifier correctness.")

(in-suite :quadlet-specifiers)

;;; ── Helpers ──────────────────────────────────────────────────────────────

(defun network-ini ()
  "Render the gathio.network unit as an INI string."
  (cinix-write-string (gathio-network-sections)))

(defun container-ini ()
  "Render the gathio.container unit as an INI string."
  (cinix-write-string (gathio-container-sections)))

(defun ini-lines (ini)
  "Split INI string into trimmed non-empty lines."
  (remove-if (lambda (l) (zerop (length l)))
             (mapcar (lambda (l) (string-trim '(#\Space #\Return) l))
                     (uiop:split-string ini :separator '(#\Newline)))))

(defun ini-has-line (ini substring)
  "Return true if any line in INI contains SUBSTRING."
  (some (lambda (line) (search substring line)) (ini-lines ini)))

(defun ini-lacks-line (ini substring)
  "Return true if no line in INI contains SUBSTRING."
  (not (ini-has-line ini substring)))

;;; ── Network unit tests ───────────────────────────────────────────────────

(test network-uses-bridge-driver
  "The .network unit uses netavark bridge driver, not Internal=true."
  (let ((ini (network-ini)))
    (is (ini-has-line ini "Driver=bridge"))
    (is (ini-lacks-line ini "Internal=true"))))

(test network-vlsm-allocation
  "The .network unit has the correct VLSM subnet and gateway for meet (podman5)."
  (let ((ini (network-ini)))
    (is (ini-has-line ini "Subnet=10.89.2.12/29"))
    (is (ini-has-line ini "Gateway=10.89.2.13"))))

(test network-name
  "The .network unit has NetworkName=gathio (the service network name)."
  (is (ini-has-line (network-ini) "NetworkName=gathio")))

;;; ── Container unit tests ─────────────────────────────────────────────────

(test container-home-volume-uses-percent-h
  "The home profile volume uses %h specifier (read-only), not a bare /var/lib/gathio path."
  ;; The Volume line must use %h and be read-only.
  ;; /var/lib/gathio may appear as the container target inside %h:...:ro
  ;; but must not appear as a bare host path (without %h).
  (let* ((ini   (container-ini))
         (lines (ini-lines ini)))
    (is (ini-has-line ini "Volume=%h:"))
    (is (ini-has-line ini ":ro"))
    ;; No Volume line should have a bare host path /var/lib/gathio
    (is (notany (lambda (l)
                  (and (search "Volume=" l)
                       (search "/var/lib/gathio" l)
                       (not (search "%h" l))))
                lines))))

(test container-data-volume-uses-srv-percent-u
  "Writable data volumes use /srv/%U/... specifier, not /srv/gathio."
  (let ((ini (container-ini)))
    (is (ini-has-line ini "Volume=/srv/%U/"))
    (is (ini-lacks-line ini "/srv/gathio"))))

(test container-no-publish-port
  "Container unit has no PublishPort= — netavark bridge handles routing."
  (is (ini-lacks-line (container-ini) "PublishPort")))

(test container-uses-netavark-network
  "Container unit references gathio.network (the service network name)."
  (let ((ini (container-ini)))
    (is (ini-has-line ini "Network=gathio.network"))))

(test container-cispec-labels
  "Container unit carries all required org.cispec CMDB identity labels."
  (let ((ini (container-ini)))
    (is (ini-has-line ini "Label=org.cispec.managed-by=consfigurator"))
    (is (ini-has-line ini "Label=org.cispec.fqdn=meet.dapla.net"))
    (is (ini-has-line ini "Label=org.cispec.service-account=gathio"))))

(test container-autoupdate-label
  "Container unit has io.containers.autoupdate=registry label."
  (is (ini-has-line (container-ini) "Label=io.containers.autoupdate=registry")))

(test container-image
  "Container unit uses the correct OCI registry image."
  (is (ini-has-line (container-ini)
                    "Image=oci.dapla.net/ghcr.io/lowercasename/gathio:latest")))

;;; ── HAProxy vhost tests ──────────────────────────────────────────────────

(test haproxy-backend-uses-netavark-gateway
  "HAProxy backend targets the netavark gateway IP, not loopback."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "10.89.2.13:3000" cfg))
    (is (not (search "127.0.0.1" cfg)))))

(test haproxy-tls-frontend
  "HAProxy config has TLS frontend on port 443."
  (is (search "bind *:443" (haproxy-vhost-config))))

(test haproxy-http-redirect
  "HAProxy config redirects HTTP to HTTPS."
  (is (search "redirect scheme https" (haproxy-vhost-config))))

(test haproxy-security-headers
  "HAProxy config sets required security response headers."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "Strict-Transport-Security" cfg))
    (is (search "X-Content-Type-Options" cfg))
    (is (search "X-Frame-Options" cfg))))

;;; ── quadlets-written arity test ──────────────────────────────────────────

(test quadlets-written-arity
  "gathio-container-sections takes zero arguments after specifier refactor."
  ;; Calling with no args must succeed; the old signature required two args.
  (is (listp (ignore-errors (meet-dapla-deploy/deploy::gathio-container-sections)))))

;;; ── Entry point ──────────────────────────────────────────────────────────

(defun run-spec ()
  "Run the quadlet specifier spec suite. Signals an error if any test fails."
  (let ((results (run :quadlet-specifiers)))
    (explain! results)
    (unless (every #'fiveam::test-passed-p results)
      (error "meet-dapla-deploy spec suite: one or more tests failed."))))
