;;;; src/docs.lisp -- meet-dapla-deploy/docs
;;;;
;;;; 40ants-doc sections for the meet-dapla-deploy system.

(defpackage :meet-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :meet-dapla-deploy/docs)

(defsection @meet-dapla-deploy (:title "meet-dapla-deploy")
  "Roswell/Consfigurator deploy of Gathio at meet.dapla.net."
  (@deploy-properties section)
  (@quadlet-builders section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (meet-dapla-deploy/deploy:zfs-encryption-key        function)
  (meet-dapla-deploy/deploy:zfs-dataset-mounted       function)
  (meet-dapla-deploy/deploy:rootless-service-account  function)
  (meet-dapla-deploy/deploy:images-pulled             function)
  (meet-dapla-deploy/deploy:quadlets-activated        function)
  (meet-dapla-deploy/deploy:deploy-app                function))

(defsection @quadlet-builders (:title "Quadlet Unit Builders")
  (meet-dapla-deploy/deploy:cinix-write-string             function)
  (meet-dapla-deploy/deploy:invidious-network-sections     function)
  (meet-dapla-deploy/deploy:invidious-db-container-sections function)
  (meet-dapla-deploy/deploy:invidious-container-sections   function)
  (meet-dapla-deploy/deploy:haproxy-vhost-config           function))
