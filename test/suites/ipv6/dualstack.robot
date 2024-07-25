*** Settings ***
Documentation       Tests related to MicroShift running in a dual stack ipv4+6 host

Resource            ../../resources/common.resource
Resource            ../../resources/oc.resource
Resource            ../../resources/ostree-health.resource
Resource            ../../resources/microshift-network.resource
Resource            ../../resources/microshift-config.resource
Library             ../../resources/libipv6.py

Suite Setup         Setup
Suite Teardown      Teardown

Test Tags           ipv6    network


*** Variables ***
${USHIFT_HOST_IP1}      ${EMPTY}
${USHIFT_HOST_IP2}      ${EMPTY}
${HOSTNAME}         hello-microshift.dualstack.cluster.local

*** Test Cases ***
Verify New Pod Works With IPv6
    [Documentation]    Verify IPv6 services are routable.
    [Setup]    Run Keywords
    ...    Save Default MicroShift Config
    ...    Migrate To Dual Stack
    ...    Create Hello MicroShift Pod
    ...    Expose Hello MicroShift Service Via Route IPv6
    ...    Restart Router

    ${pod_ip}=    Run With Kubeconfig    oc get pod hello-microshift -n ${NAMESPACE} -o jsonpath='{.status.podIPs[0].ip}'
    Must Not Be Ipv6    ${pod_ip}
    ${pod_ip}=    Run With Kubeconfig    oc get pod hello-microshift -n ${NAMESPACE} -o jsonpath='{.status.podIPs[1].ip}'
    Must Be Ipv6    ${pod_ip}
    ${service_ip}=    Run With Kubeconfig    oc get svc hello-microshift -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}'
    Must Be Ipv6    ${service_ip}
    

    Wait Until Keyword Succeeds    10x    6s
    ...    Access Hello Microshift Success    ushift_ip=${USHIFT_HOST_IP1}    ushift_port=${HTTP_PORT}    hostname=${HOSTNAME}
    Wait Until Keyword Succeeds    10x    6s
    ...    Access Hello Microshift Success    ushift_ip=${USHIFT_HOST_IP2}    ushift_port=${HTTP_PORT}    hostname=${HOSTNAME}

    [Teardown]    Run Keywords
    ...    Delete Hello MicroShift Route
    ...    Delete Hello MicroShift Pod And Service
    ...    Wait For Service Deletion With Timeout
    ...    Restore Default MicroShift Config
    ...    Restart MicroShift

Verify New Pod Works With IPv4
    [Documentation]    Verify IPv4 services are routable.
    [Setup]    Run Keywords
    ...    Save Default MicroShift Config
    ...    Migrate To Dual Stack
    ...    Create Hello MicroShift Pod
    ...    Expose Hello MicroShift Service Via Route IPv4
    ...    Restart Router

    ${pod_ip}=    Run With Kubeconfig    oc get pod hello-microshift -n ${NAMESPACE} -o jsonpath='{.status.podIPs[0].ip}'
    Must Not Be Ipv6    ${pod_ip}
    ${pod_ip}=    Run With Kubeconfig    oc get pod hello-microshift -n ${NAMESPACE} -o jsonpath='{.status.podIPs[1].ip}'
    Must Be Ipv6    ${pod_ip}
    ${service_ip}=    Run With Kubeconfig    oc get svc hello-microshift -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}'
    Must Not Be Ipv6    ${service_ip}
    

    Wait Until Keyword Succeeds    10x    6s
    ...    Access Hello Microshift Success    ushift_ip=${USHIFT_HOST_IP1}    ushift_port=${HTTP_PORT}    hostname=${HOSTNAME}
    Wait Until Keyword Succeeds    10x    6s
    ...    Access Hello Microshift Success    ushift_ip=${USHIFT_HOST_IP2}    ushift_port=${HTTP_PORT}    hostname=${HOSTNAME}

    [Teardown]    Run Keywords
    ...    Delete Hello MicroShift Route
    ...    Delete Hello MicroShift Pod And Service
    ...    Wait For Service Deletion With Timeout
    ...    Restore Default MicroShift Config
    ...    Restart MicroShift


*** Keywords ***
Setup
    [Documentation]    Test suite setup
    Initialize Global Variables
    Login MicroShift Host
    Setup Suite With Namespace
    Wait Until Greenboot Health Check Exited

Teardown
    [Documentation]    Test suite teardown
    Teardown Suite With Namespace
    Logout MicroShift Host

Initialize Global Variables
    [Documentation]    Initializes global variables.
    Log    IP1: ${USHIFT_HOST_IP1} IPv6: ${USHIFT_HOST_IP2}
    Should Not Be Empty    ${USHIFT_HOST_IP1}    USHIFT_HOST_IP1 variable is required
    Should Not Be Empty    ${USHIFT_HOST_IP2}    USHIFT_HOST_IP2 variable is required

Migrate To Dual Stack
    [Documentation]    Configure MicroShift to enable dual stack network

    ${dual_stack}=    CATENATE    SEPARATOR=\n
    ...    ---
    ...    network:
    ...    \ \ clusterNetwork: [10.42.0.0/16, fd01::/48]
    ...    \ \ serviceNetwork: [10.43.0.0/16, fd02::/112]
    ${replaced}=    Replace MicroShift Config    ${dual_stack}
    Upload MicroShift Config    ${replaced}
    Restart MicroShift

Delete Hello MicroShift Route
    [Documentation]    Delete route for cleanup.
    Oc Delete    route/hello-microshift -n ${NAMESPACE}

Wait For Service Deletion With Timeout
    [Documentation]    Polls for service and endpoint by "app=hello-microshift" label. Fails if timeout
    ...    expires. This check is unique to this test suite because each test here reuses the same namespace. Since
    ...    the tests reuse the service name, a small race window exists between the teardown of one test and the setup
    ...    of the next. This produces flakey failures when the service or endpoint names collide.
    Wait Until Keyword Succeeds    30s    1s
    ...    Network APIs With Test Label Are Gone

Expose Hello MicroShift Service Via Route IPv4
    [Documentation]    Expose the "hello microshift" application through the Route
    Run With Kubeconfig    oc apply -n ${NAMESPACE} -f assets/hello-microshift-service.yaml
    Oc Expose    svc hello-microshift --hostname ${HOSTNAME} -n ${NAMESPACE}

Expose Hello MicroShift Service Via Route IPv6
    [Documentation]    Expose the "hello microshift" application through the Route
    Run With Kubeconfig    oc apply -n ${NAMESPACE} -f assets/hello-microshift-service-ipv6.yaml
    Oc Expose    svc hello-microshift --hostname ${HOSTNAME} -n ${NAMESPACE}

Network APIs With Test Label Are Gone
    [Documentation]    Check for service and endpoint by "app=hello-microshift" label. Succeeds if response matches
    ...    "No resources found in <namespace> namespace." Fail if not.
    ${match_string}=    Catenate    No resources found in    ${NAMESPACE}    namespace.
    ${match_string}=    Remove String    ${match_string}    "
    ${response}=    Run With Kubeconfig    oc get svc,ep -l app\=hello-microshift -n ${NAMESPACE}
    Should Be Equal As Strings    ${match_string}    ${response}    strip_spaces=True

DNS Entry For Route Should Resolve
    [Documentation]    Resolve hello-microshift route via mDNS from the hypervisor/RF runner.
    ...    Expects RF runner host has opened port 5353 for libvirt zone.

    ${result}=    Run Process
    ...    avahi-resolve-host-name ${HOSTNAME}
    ...    shell=True
    ...    timeout=15s
    Should Be Equal As Integers    0    ${result.rc}
    Log Many    ${result.stdout}    ${result.stderr}
    @{words}=    Split String    ${result.stdout}
    Must Be Ipv6    ${words}[1]

Restart Router
    [Documentation]    Restart the router and wait for readiness again. The router is sensitive to apiserver
    ...    downtime and might need a restart (after the apiserver is ready) to resync all the routes.
    Run With Kubeconfig    oc rollout restart deployment router-default -n openshift-ingress
    Named Deployment Should Be Available    router-default    openshift-ingress    5m

All Services Are Ipv6
    [Documentation]    Retrieve all services and check none of them have an IPv4 family
    ${response}=    Run With Kubeconfig    oc get svc -A -o jsonpath='{.items[*].spec.ipFamilies[*]}'
    Should Not Contain    ${response}    IPv4
