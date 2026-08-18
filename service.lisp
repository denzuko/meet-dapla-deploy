(:repo-name    'meet-dapla-deploy'
 :system-name  'meet-dapla-deploy'
 :fqdn         'meet.dapla.net'
 :vhost-name   'meet'
 :service-user 'gathio'
 :description  'Gathio event management'
 :image        'oci.dapla.net/ghcr.io/lowercasename/gathio:latest'
 :internal-port 3000
 :health-path  '/'
 :extra-images ('oci.dapla.net/library/mongo:6')
 :datasets
 (  (:name 'users/gathio'
   :mountpoint '/var/lib/gathio'
   :purpose 'Service account home directory')
  (:name 'containers/gathio-db'
   :mountpoint '/srv/gathio/db'
   :purpose 'MongoDB data directory')
  (:name 'containers/gathio-events'
   :mountpoint '/srv/gathio/events'
   :purpose 'Gathio event image store'))
)
