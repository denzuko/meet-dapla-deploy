;;;; src/deploy.lisp -- meet-dapla-deploy/deploy core package
;;;;
;;;; Consfigurator properties and DEFHOST for the Gathio stack at
;;;; meet.dapla.net. meet-dapla-deploy.ros is a thin command wrapper.

(defpackage :meet-dapla-deploy/deploy
  (:use :cl)
  (:import-from :consfigurator
                :defprop :defhost :deploy :run :mrun :stripln
                :remote-exists-p :write-remote-file :on-change)
  (:import-from :consfigurator.property.file
                :has-content :containing-directory-exists)
  (:import-from :consfigurator.property.systemd :lingering-enabled)
  (:import-from :consfigurator.property.service :reloaded)
  (:export :*service-user* :*home-dataset* :*home-mountpoint*
           :*data-dataset* :*data-mountpoint*
           :*events-dataset* :*events-mountpoint*
           :*home-dataset-keyfile* :*data-dataset-keyfile*
           :*events-dataset-keyfile*
           :*secrets-path* :*haproxy-fqdn*
           :deploy-app
           :zfs-encryption-key :zfs-dataset-mounted
           :rootless-service-account
           :images-pulled :quadlets-activated
           :cinix-write-string
           :service-account-uid
           :quadlets-written
           :haproxy-vhost-written
           :gathio-network-sections
           :gathio-db-container-sections
           :gathio-container-sections
           :haproxy-vhost-config))

(in-package :meet-dapla-deploy/deploy)

(defparameter *service-user* "gathio"
  "Rootless system account the quadlets run under.")
(defparameter *home-dataset* "storage/users/gathio")
(defparameter *home-mountpoint* "/var/lib/gathio")
(defparameter *home-dataset-keyfile* "/etc/zfs-keys/gathio-users.key")
(defparameter *data-dataset* "storage/containers/gathio-db")
(defparameter *data-mountpoint* "/srv/gathio/db"
  "MongoDB data directory.")
(defparameter *data-dataset-keyfile* "/etc/zfs-keys/gathio-db.key")
(defparameter *events-dataset* "storage/containers/gathio-events")
(defparameter *events-mountpoint* "/srv/gathio/events"
  "Gathio event image storage, mounted into the app container.")
(defparameter *events-dataset-keyfile* "/etc/zfs-keys/gathio-events.key")
(defparameter *secrets-path* "/var/lib/gathio/.env/db"
  "Generated once; holds MONGO_ROOT_PASSWORD for gathio-db.")
(defparameter *haproxy-fqdn* "meet.dapla.net")
(defparameter *haproxy-vhost-name* "meet")

(defprop zfs-encryption-key :posix (path)
  "Generate a raw 32-byte ZFS encryption key at PATH via `openssl rand -out`,
   once, left alone on redeploy. The key is written directly by openssl to
   avoid binary corruption through shell capture and string re-encoding."
  (:desc (format nil "ZFS encryption key at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (mrun "openssl" "rand" "-out" path "32")
   (mrun "chmod" "600" path)))

(defun zfs-create-command (dataset mountpoint keyfile)
  "The `zfs create` command line for DATASET at MOUNTPOINT, with
   AES-256-GCM encryption keyed from KEYFILE when supplied."
  (if keyfile
      (format nil "zfs create -o mountpoint=~A -o encryption=aes-256-gcm -o keyformat=raw -o keylocation=file://~A ~A"
              mountpoint keyfile dataset)
      (format nil "zfs create -o mountpoint=~A ~A" mountpoint dataset)))

(defprop zfs-dataset-mounted :posix (dataset mountpoint &optional keyfile)
  "Ensure DATASET exists, mounted at MOUNTPOINT. When KEYFILE is given the
   dataset is created with AES-256-GCM native encryption. If the dataset
   exists but is not mounted, the key is loaded and the dataset mounted."
  (:desc (format nil "ZFS dataset ~A mounted at ~A~:[~; (encrypted)~]"
                  dataset mountpoint keyfile))
  (:check
   (multiple-value-bind (out err exit)
       (run :may-fail (format nil "zfs get -H -o value mounted ~A" dataset))
     (declare (ignore err))
     (and (zerop exit) (string= "yes" (stripln out)))))
  (:apply
   (if (zerop (mrun :for-exit (format nil "zfs list -H -o name ~A" dataset)))
       (progn
         (when keyfile (mrun (format nil "zfs load-key ~A" dataset)))
         (mrun (format nil "zfs mount ~A" dataset)))
       (mrun (zfs-create-command dataset mountpoint keyfile)))))

(defprop rootless-service-account :posix (username home)
  "Ensure a system account USERNAME exists with home directory HOME,
   without creating that directory."
  (:desc (format nil "System account ~A at ~A" username home))
  (:check (zerop (mrun :for-exit "id" username)))
  (:apply (mrun "useradd" "--system" "--no-create-home"
                "--home-dir" home username)))

(defprop db-secret-file :posix (path user)
  "Generate the MongoDB root password once via `openssl rand -hex 32` and
   persist it at PATH, mode 0600, owned by USER. Left alone on redeploy.
   CONTAINING-DIRECTORY-EXISTS is always called first."
  (:desc (format nil "DB secret at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (let ((pass (stripln (mrun "openssl" "rand" "-hex" "32"))))
     (write-remote-file
      path
      (format nil "MONGO_INITDB_ROOT_USERNAME=gathio~%MONGO_INITDB_ROOT_PASSWORD=~A~%MONGO_INITDB_DATABASE=gathio~%"
              pass)
      :mode #o600)
     (mrun "chown" (format nil "~A:~A" user user) path))))

(defprop images-pulled :posix (user &rest images)
  "Pull IMAGES into USER's rootless Podman image store via `machinectl shell`."
  (:desc (format nil "Podman images pulled for ~A" user))
  (:check
   (every (lambda (image)
            (zerop (mrun :for-exit
                    (format nil "machinectl shell ~A@ /usr/bin/podman image exists ~A"
                            user image))))
          images))
  (:apply
   (dolist (image images)
     (mrun (format nil "machinectl shell ~A@ /usr/bin/podman pull ~A" user image)))))

(defun cinix-write-string (sections)
  "Serialize an alist of (section-name . ((key . value) ...)) into
   INI/systemd unit-file text."
  (with-output-to-string (s)
    (dolist (section sections)
      (format s "[~A]~%" (car section))
      (dolist (kv (cdr section))
        (format s "~A=~A~%" (car kv) (cdr kv)))
      (format s "~%"))))

(defun service-account-uid (username)
  "Read USERNAME's UID from the local passwd database via getent, at
   property apply time after ROOTLESS-SERVICE-ACCOUNT has run. The UID
   is used as the loopback PublishPort, per dapla.net convention.
   Returns NIL if the account does not yet exist, allowing callers to
   skip operations that depend on the UID."
  (let ((raw (with-output-to-string (s)
               (uiop:run-program (list "getent" "passwd" username)
                                 :output s
                                 :ignore-error-status t))))
    (when (and raw (plusp (length (string-trim '(#\Newline #\Space) raw))))
      (parse-integer
       (third
        (uiop:split-string
         (string-trim '(#\Newline #\Space) raw)
         :separator '(#\:)))))))

(defun gathio-network-sections ()
  "Cinix AST for gathio.network: internal-only network."
  '(("Network" . (("NetworkName" . "gathio")
                  ("Internal"    . "true")))))

(defun gathio-db-container-sections (data-mountpoint)
  "Cinix AST for gathio-db.container: mongo:6, ZFS-backed volume,
   health-checked via mongosh ping."
  `(("Unit" . (("Description" . "Gathio MongoDB database")))
    ("Container" . (("Image"         . "oci.dapla.net/library/mongo:6")
                    ("ContainerName" . "gathio-db")
                    ("AutoUpdate"    . "registry")
                    ("EnvironmentFile" . "%S/gathio/db.env")
                    ("Volume"        . ,(format nil "~A:/data/db:Z" data-mountpoint))
                    ("Network"       . "gathio.network")
                    ("HealthCmd"     . "mongosh --quiet --eval \"db.adminCommand('ping').ok\" || exit 1")
                    ("HealthStartPeriod" . "15s")
                    ("HealthInterval"    . "30s")
                    ("HealthTimeout"     . "10s")
                    ("HealthRetries"     . "5")))
    ("Service" . (("Restart"         . "on-failure")
                  ("TimeoutStartSec" . "120")
                  ("TimeoutStopSec"  . "30")))
    ("Install" . (("WantedBy" . "default.target")))))

(defun gathio-container-sections (events-mountpoint secrets-path)
  "Cinix AST for gathio.container: binds to 127.0.0.1 only, mounts the
   event images volume and the env secret. Outbound mail routes through
   the panix.com smarthost configured via the env file. The loopback port
   is the service account UID, per dapla.net convention."
  (let ((port (service-account-uid *service-user*)))
    `(("Unit" . (("Description" . "Gathio event management")
                 ("After"       . "network-online.target gathio-db.service")
                 ("Wants"       . "network-online.target")
                 ("Requires"    . "gathio-db.service")))
      ("Container" . (("Image"           . "oci.dapla.net/ghcr.io/lowercasename/gathio:latest")
                      ("ContainerName"   . "gathio")
                      ("AutoUpdate"      . "registry")
                      ("PublishPort"     . ,(format nil "127.0.0.1:~A:~A" port port))
                      ("EnvironmentFile" . ,secrets-path)
                      ("Volume"          . ,(format nil "~A:/app/public/events:Z"
                                                    events-mountpoint))
                      ("Network"         . "gathio.network")
                      ("Label"           . "io.containers.autoupdate=registry")))
      ("Service" . (("Restart"         . "on-failure")
                    ("TimeoutStartSec" . "120")
                    ("TimeoutStopSec"  . "30")))
      ("Install" . (("WantedBy" . "default.target"))))))

(defun haproxy-vhost-config ()
  "HAProxy vhost text: HTTP redirect, TLS frontend with security headers
   and iCal/AP-friendly buffer sizing, backend health-checked against
   gathio on loopback. Backend port is the service account UID, per
   dapla.net convention."
  (let ((port (service-account-uid *service-user*)))
  (format nil
"frontend ~A_http
  bind *:80
  acl host_~A hdr(host) -i ~A
  redirect scheme https code 301 if host_~A

frontend ~A_https
  bind *:443 ssl crt /etc/haproxy/certs/~A.pem alpn h2,http/1.1
  acl host_~A hdr(host) -i ~A
  option http-buffer-request
  tune.bufsize 131072
  http-response set-header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"
  http-response set-header X-Content-Type-Options nosniff
  http-response set-header X-Frame-Options SAMEORIGIN
  http-response set-header Referrer-Policy strict-origin-when-cross-origin
  http-response set-header Permissions-Policy \"interest-cohort=()\"
  use_backend ~A_be if host_~A

backend ~A_be
  balance roundrobin
  option httpchk GET /
  http-check expect status 200
  timeout connect 5s
  timeout server  60s
  server gathio 127.0.0.1:~A check inter 10s rise 2 fall 3
"
          *haproxy-vhost-name* *haproxy-vhost-name* *haproxy-fqdn* *haproxy-vhost-name*
          *haproxy-vhost-name* *haproxy-fqdn*
          *haproxy-vhost-name* *haproxy-fqdn*
          *haproxy-vhost-name* *haproxy-vhost-name*
          *haproxy-vhost-name*
          port)))

(defprop quadlets-written :posix (user home data-mountpoint events-mountpoint secrets-path)
  "Write all Gathio quadlet unit files into USER's systemd container
   directory. UID is read at apply time via getent, after
   ROOTLESS-SERVICE-ACCOUNT has run, so PublishPort is always correct."
  (:desc (format nil "Gathio quadlet units written for ~A" user))
  (:apply
   (let ((quadlet-dir (format nil "~A/.config/containers/systemd" home)))
     (consfigurator.property.file:containing-directory-exists
      (format nil "~A/gathio.network" quadlet-dir))
     (write-remote-file
      (format nil "~A/gathio.network" quadlet-dir)
      (cinix-write-string (gathio-network-sections)))
     (write-remote-file
      (format nil "~A/gathio-db.container" quadlet-dir)
      (cinix-write-string (gathio-db-container-sections data-mountpoint)))
     (write-remote-file
      (format nil "~A/gathio.container" quadlet-dir)
      (cinix-write-string (gathio-container-sections events-mountpoint secrets-path))))))

(defprop quadlets-activated :posix (user)
  "Reload USER's user-scope systemd daemon and restart the gathio
   quadlet-generated services via `machinectl shell`."
  (:desc (format nil "Quadlets activated for ~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user daemon-reload" user))
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user restart gathio-db gathio"
                 user))))


(defprop haproxy-vhost-written :posix ()
  "Write the HAProxy vhost config for this service. Skipped when the
   service account does not yet exist, since the port cannot be determined.
   Reloads HAProxy only when content changes."
  (:desc (format nil "HAProxy vhost written for ~A" *haproxy-fqdn*))
  (:check (null (service-account-uid *service-user*)))
  (:apply
   (let ((port (service-account-uid *service-user*)))
     (unless port
       (consfigurator:inapplicable-property
        "Service account ~A does not exist; cannot determine port."
        *service-user*))
     (let* ((cfg-path (format nil "/etc/haproxy/conf.d/~A.cfg" *haproxy-vhost-name*))
            (new-content (haproxy-vhost-config))
            (current (when (probe-file cfg-path)
                       (uiop:read-file-string cfg-path))))
       (unless (equal new-content current)
         (containing-directory-exists cfg-path)
         (write-remote-file cfg-path new-content)
         (consfigurator.property.service:reloaded "haproxy"))))))

(defhost gathio-host (:deploy (:local))
  "The Gathio stack's host: three AES-256-GCM-encrypted ZFS datasets
   (home, MongoDB data, event images), the rootless service account and
   its linger, the generated DB secret, pulled images, the three quadlet
   units, and the HAProxy vhost, applied in dependency order."
  (zfs-encryption-key *home-dataset-keyfile*)
  (zfs-encryption-key *data-dataset-keyfile*)
  (zfs-encryption-key *events-dataset-keyfile*)
  (zfs-dataset-mounted *home-dataset*   *home-mountpoint*   *home-dataset-keyfile*)
  (zfs-dataset-mounted *data-dataset*   *data-mountpoint*   *data-dataset-keyfile*)
  (zfs-dataset-mounted *events-dataset* *events-mountpoint* *events-dataset-keyfile*)
  (rootless-service-account *service-user* *home-mountpoint*)
  (lingering-enabled *service-user*)
  (db-secret-file *secrets-path* *service-user*)
  (images-pulled *service-user*
                  "oci.dapla.net/library/mongo:6"
                  "oci.dapla.net/ghcr.io/lowercasename/gathio:latest")
  (quadlets-written *service-user* *home-mountpoint*
                    *data-mountpoint* *events-mountpoint* *secrets-path*)
  (quadlets-activated *service-user*)
  (haproxy-vhost-written))

(defun deploy-app ()
  "Provision the Gathio stack via GATHIO-HOST (Consfigurator, :local
   connection). Aborts loudly if any property is skipped."
  (format t "~&--> Provisioning via Consfigurator (GATHIO-HOST)...~%")
  (let ((provisioning-failed nil))
    (handler-bind ((consfigurator::skipped-properties
                     (lambda (c) (declare (ignore c))
                       (setf provisioning-failed t))))
      (gathio-host))
    (when provisioning-failed
      (error "GATHIO-HOST provisioning reported failed properties ~
              (see the per-property report above). Refusing to proceed.")))
  (format t "~&--> Gathio stack provisioned. Visit https://~A~%" *haproxy-fqdn*))
