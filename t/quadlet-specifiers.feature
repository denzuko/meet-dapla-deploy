Feature: Quadlet unit template specifiers
  As a dapla.net operator
  I want quadlet unit files to use systemd specifiers instead of hardcoded paths
  So that units are portable across service account UIDs, home directories,
  and storage layouts without regeneration

  Background:
    Given the Gathio stack deploy.lisp is loaded
    And the cinix-write-string function is available

  Scenario: Network unit uses netavark bridge driver with VLSM allocation
    When gathio-network-sections is called
    Then the INI output contains "Driver=bridge"
    And the INI output contains "Subnet=10.89.2.12/29"
    And the INI output contains "Gateway=10.89.2.13"
    And the INI output does not contain "Internal=true"

  Scenario: Container unit mounts home profile read-only via %h specifier
    When gathio-container-sections is called
    Then the INI output contains a Volume line starting with "%h:"
    And that Volume line ends with ":ro"
    And the INI output does not contain "/var/lib/gathio"

  Scenario: Container unit mounts writable data via /srv/%U specifier
    When gathio-container-sections is called
    Then the INI output contains a Volume line starting with "/srv/%U/"
    And that Volume line does not end with ":ro"
    And the INI output does not contain "/srv/gathio"

  Scenario: Container unit org.cispec labels are present
    When gathio-container-sections is called
    Then the INI output contains "Label=org.cispec.managed-by=consfigurator"
    And the INI output contains "Label=org.cispec.fqdn=meet.dapla.net"
    And the INI output contains "Label=org.cispec.service-account=gathio"

  Scenario: Container unit uses netavark network by name
    When gathio-container-sections is called
    Then the INI output contains "Network=meet.network"
    And the INI output does not contain "PublishPort"

  Scenario: HAProxy backend targets netavark gateway IP
    When haproxy-vhost-config is called
    Then the output contains "10.89.2.13:3000"
    And the output does not contain "127.0.0.1"

  Scenario: quadlets-written defprop takes only user and home arguments
    Then quadlets-written has arity 2 (user home)
    And quadlets-written does not accept data-mountpoint as an argument
    And quadlets-written does not accept events-mountpoint as an argument

  Scenario: decommissioned teardown follows ordered steps
    When decommissioned is called with user "gathio"
    Then step 1 stops all containers via machinectl
    Then step 2 removes the HAProxy vhost config
    Then step 3 reloads HAProxy
    Then step 4 terminates the login session
    Then step 5 disables linger
    Then step 6 deletes the service account
    Then step 7 destroys ZFS datasets
    Then step 8 removes ZFS key files
