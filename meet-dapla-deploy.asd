;;;; meet-dapla-deploy.asd

(asdf:defsystem :meet-dapla-deploy)

(asdf:defsystem :meet-dapla-deploy/deploy
  :description "Roswell/Consfigurator deploy of Gathio on rootless Podman
quadlets behind HAProxy at meet.dapla.net."
  :license "BSD-3-Clause"
  :depends-on (:cl-inix :consfigurator)
  :components ((:file "src/deploy"))
  :in-order-to ((asdf:test-op (asdf:test-op :meet-dapla-deploy/e2e))))

(asdf:defsystem :meet-dapla-deploy/docs
  :depends-on (:meet-dapla-deploy/deploy :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs")))

(asdf:defsystem :meet-dapla-deploy/e2e
  :depends-on (:meet-dapla-deploy/deploy :fiveam :dexador)
  :components ((:file "t/e2e"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :meet-dapla-deploy-e2e)))

(asdf:defsystem :meet-dapla-deploy/spec
  :description "FiveAM specification tests for the quadlet template specifier refactor."
  :depends-on (:meet-dapla-deploy/deploy :fiveam)
  :components ((:file "t/spec"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :meet-dapla-deploy/spec :run-spec)))
