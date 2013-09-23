Poor Man Central SCAP
=====================

Introduction
------------

When working with SCAP content for its various use cases, there are already a
few open source projects that provide us with SCAP scanners. Open-SCAP is able
to test OVAL and XCCDF documents, but only locally (thus far). Ovaldi is a
similar one.

What is missing is a way to centrally work on SCAP content, having multiple
systems pull the necessary definitions from the central repository, "play" it
locally and send back the results to a central location.

There, on this central location, the reports can then be aggregated further to
make proper architectural decisions with a wider view on the situation, rather
than having to parse the reports individually.

Central management of SCAP content
----------------------------------

SCAP 1.2 already provides a way to have a single stream (SCAP data streams)
containing all SCAP content needed for a local system to properly test all that
is needed.

pmcs will use SCAP data streams by bundling the XCCDF, OVAL, CPE (and in the
future other protocols as well) for each target based on a prepared definition,
and offering the SCAP data stream as a single HTTP(S) resource.

Local SCAP scanners pull the SCAP data stream(s) needed for the system, based on
a set of system parameters (hostname, domainname, platform, class and generic
keywords). They evaluate the SCAP data stream(s) and send back the reports
towards a central repository.

Currently, the two "central" locations supported are regular file systems (in
case of file shares), using "file://" as the "remote" pointer, and web servers,
using "http://" or "https://" as "remote" pointer.

SCAP content repositories
-------------------------

The SCAP content needs to be managed outside, but pmcs can help a bit. It
includes a scaprepo example to show how external repositories can be refreshed
(for those definitions that are needed).

If own development is needed, there is also a script that helps creating OVAL
files based on separate snippets.

Configurationless approach
--------------------------

One of the focus areas of pmcs is that the local components use SCAP scanners
already available. The first focus is on Open-SCAP and Ovaldi, but others should
be easy to integrate as we are focusing on the SCAP technologies.

The local pmcs agent has two roles: scheduling regular SCAP evaluations, and
waiting for triggers to do ad-hoc evaluations.

The scheduled evaluation does not need a daemonized agent; it can be perfectly
scheduled from a scheduler such as Cron, Windows Task Scheduler or even more
enterprise job schedulers. But we will support the daemonized approach as well
where the admin can trigger evaluations.

Only a single parameter should be passed on to the agent: the URN towards the
central configuration repository. For instance (pmcsa = pmcs agent):
```
~$ pmcsa https://cscapserver.localdomain/repo
```

The agent will then pull in the necessary information from this location.

Once information is obtained, the agent will download the SCAP content that it
needs to evaluate, evaluate it, and send the results to a central repository
(which does not need to be the same URN as the central configuration
repository).

Checking order
--------------

To handle the configuration as well as SCAP content in a manageable manner, the
agent will always look through the repository using the following list:

* Host-specific at `hosts/MYFQDN` using a fully qualified hostname
* Domain-specific with class and platform information at
  `domains/MYDOMAIN/classes/MYCLASS/platforms/MYPLATFORM` (only for SCAP data
  streams)
* Domain-specific with class information at `domains/MYDOMAIN/classes/MYCLASS` using the class
* Class-specific at `classes/MYCLASS/platforms/MYPLATFORM` (only for SCAP data
  streams)
* Class-specific at `classes/MYCLASS` using the class
* Domain-specific without class information at `domains/MYDOMAIN`
* Keyword-triggered (only for SCAP data streams) at `keywords/MYKEYWORD` using the
  keyword (only for SCAP data streams)

So to obtain system configuration information, the configuration will be pulled
in the reverse order, overriding values as they come along. So the domain
configuration might say `platform=Gentoo Linux` but if the host-specific one
sais `platform=Windows Server 2012` then the latter "wins".

To obtain SCAP data stream(s), *all* hits are used (a system can evaluate
various SCAP data streams).

Reporting repository
--------------------

The evaluated results are sent to a central repository. There, a per-host result
directory is kept for each day (for the scheduled streams) or invocation (for
the ad-hoc results).

### Generating reports ###

Reports are made off-line (so not on retrieval of the data). This is not only to
keep the code simple and segregated, but also from a security point of view -
directly triggering processing upon retrieval of a file opens more access
vectors to exploit - and we don't want that do we.

Hence the repository itself only stores the files on the file system, doing a
simple check that the retrieved file and origin (FQDN) matches the remote IP
address that is connected to the infrastructure. A set of systems can be added
to the access control lists if central SCAP scanning is performed (for instance
to scan remote database systems) and the results are submitted to the reporting
repository.

The reports themselves are either batch-triggered or event-triggered. This event
can be whatever you want - in the pmcs code we will use log scanning, where the
access log of the reporting server is used as the source of the events.

### Default reports ###

In pmcs three sets of default reports will be supported, but of course you are
free to implement your own.

- The first one will give an overview of all tests that have been ran (and their
  state) for a system, given its FQDN (so there will be daily, per-system
  reports). This is for OVAL results.
- The second one will give an overview of all systems for which a test has been
  run (and their state). This allows administrators or security admins to see
  the state of the entire environment for a particular rule. This is for OVAL
  results.
- For each XCCDF tested (well, result received) a report will be generated that
  contains the state of all tests for all servers for which the XCCDF has been
  ran.

Next to the default reports, an example will be provided where the results are
parsed by open-scap to generate its default reports.
Ad-hoc invocations
------------------

Sometimes administrators want to push out certain checks towards one or more
systems without having to wait for a particular scheduled run. We need to
support this, which means that the pmcsa (pmsc agent) will also support a
daemonized setup to which administrators can push evaluation requests (using
pmcsc - pmcs client):
```
~$ pmcsc eval check-cvs-2013-2332 class=unix
```

The client in the above case will check what the target systems are with the
"unix" class, and then push out the request to evaluate the given data stream.
The daemonized agents will pull this data stream from the `ad-hoc/` location,
evaluate and send it to the central report location where the reports are stored
in a specific ad-hoc location, with the results for each server.

External software requirements
------------------------------

The pmcs setup wouldn't be a "poor man" setup if we wouldn't leverage existing
infrastructure as much as possible.

* To build the SCAP data streams, we assume the administrator does this himself.
  This can be accomplished with tools such as open-scap.
* The first central repositories are simple HTTP directory structures; pmcs will
  provide a few scripts to easily manage those. The idea is that, if you want to
  manage this repository, it is assumed you use a git (or other version control
  system) repository.
* The target repository to save files in will, at first, be a simple CGI script
  to run on a web server. Authentication against the repositories is assumed to
  be handled using the system's server certificates if applicable.


