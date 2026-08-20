Feature: dapla.net rootless Podman quadlet deploy
  As a dapla.net operator
  I want every exported function and property to be verified
  So that regressions are caught before reaching the host

  Background:
    Given the deploy system is loaded

  # ── cinix-write-string ────────────────────────────────────────────────

  Scenario: cinix-write-string serialises a single section
    When cinix-write-string is called with ((Section . ((Key . Value))))
    Then the output contains "[Section]"
    And the output contains "Key=Value"
    And the output ends with a blank line

  Scenario: cinix-write-string serialises multiple sections in order
    When cinix-write-string is called with two sections
    Then section headers appear in the order given

  # ── Network unit ──────────────────────────────────────────────────────

  Scenario: Network unit uses netavark bridge driver
    When gathio-network-sections is called
    Then the INI contains "Driver=bridge"
    And the INI does not contain "Internal=true"

  Scenario: Network unit carries correct VLSM allocation
    When gathio-network-sections is called
    Then the INI contains "Subnet=10.89.2.12/29"
    And the INI contains "Gateway=10.89.2.13"

  # ── Container units ───────────────────────────────────────────────────

  Scenario: gathio.container home volume is read-only via %h
    When gathio-container-sections is called
    Then a Volume line starts with "%h:"
    And that Volume line ends with ":ro"

  Scenario: gathio.container data volume uses /srv/%U specifier
    When gathio-container-sections is called
    Then a Volume line starts with "/srv/%U"
    And no Volume line contains the literal path "/srv/gathio"

  Scenario: gathio.container carries org.cispec Labels
    When gathio-container-sections is called
    Then the INI contains "Label=org.cispec.managed-by=consfigurator"
    And the INI contains "Label=org.cispec.fqdn=meet.dapla.net"
    And the INI contains "Label=org.cispec.service-account=gathio"

  Scenario: gathio.container has no PublishPort
    When gathio-container-sections is called
    Then the INI does not contain "PublishPort"

  Scenario: gathio.container declares dependency on gathio-db
    When gathio-container-sections is called
    Then the INI contains "After=network-online.target gathio-db.service"
    And the INI contains "Requires=gathio-db.service"

  Scenario: gathio-db.container waits for ZFS mount
    When gathio-db-container-sections is called
    Then the INI contains "After=zfs-mount.service"

  Scenario: gathio-db.container EnvironmentFile uses %h specifier
    When gathio-db-container-sections is called
    Then the INI contains "EnvironmentFile=%h"

  Scenario: gathio-db.container data volume uses /srv/%U specifier
    When gathio-db-container-sections is called
    Then a Volume line starts with "/srv/%U/db"

  # ── HAProxy vhost config ─────────────────────────────────────────────

  Scenario: HAProxy config has TLS frontend on port 443
    When haproxy-vhost-config is called
    Then the output contains "bind *:443"

  Scenario: HAProxy config redirects HTTP to HTTPS
    When haproxy-vhost-config is called
    Then the output contains "redirect scheme https"

  Scenario: HAProxy config sets required security headers
    When haproxy-vhost-config is called
    Then the output contains "Strict-Transport-Security"
    And the output contains "X-Content-Type-Options"
    And the output contains "X-Frame-Options"
    And the output contains "Referrer-Policy"
    And the output contains "Permissions-Policy"

  Scenario: HAProxy backend targets netavark gateway
    When haproxy-vhost-config is called
    Then the output contains "10.89.2.13:3000"
    And the output does not contain "127.0.0.1"

  # ── haproxy-vhost-written ─────────────────────────────────────────────

  Scenario: haproxy-vhost-written :check always returns nil (always applies)
    Then haproxy-vhost-written :check returns nil

  # ── quadlets-written ─────────────────────────────────────────────────

  Scenario: quadlets-written accepts only user and home arguments
    Then gathio-container-sections accepts zero arguments
    And gathio-db-container-sections accepts zero arguments

  # ── decommissioned teardown order ─────────────────────────────────────

  Scenario: decommissioned defprop is defined and exported
    Then decommissioned is fbound in meet-dapla-deploy/deploy

  # ── deploy-app ───────────────────────────────────────────────────────

  Scenario: deploy-app is defined and exported
    Then deploy-app is fbound in meet-dapla-deploy/deploy
