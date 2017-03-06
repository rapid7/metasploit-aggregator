Metasploit [![Build Status](https://travis-ci.org/rapid7/metasploit-aggregator.svg?branch=master)](https://travis-ci.org/rapid7/metasploit-aggregator) [![Code Climate](https://img.shields.io/codeclimate/github/rapid7/metasploit-aggregator.svg)](https://codeclimate.com/github/rapid7/metasploit-aggregator)
==
The Metasploit Aggregator is released under a BSD-style license. See
COPYING for more details.

Bug tracking and development information can be found at:
 https://github.com/rapid7/metasploit-aggregator

New bugs and feature requests should be directed to:
  http://r-7.co/MSF-BUGv1

API documentation for writing modules can be found at:
  https://rapid7.github.io/metasploit-aggregator/api

Questions and suggestions can be sent to:
  https://lists.sourceforge.net/lists/listinfo/metasploit-hackers

## Metasploit Aggregator

The Metasploit Aggregator is a proxy for Meterpreter sessions. Normally, Meterpreter sessions connect directly to a Metasploit listener. However, this has a few problems:

 1. Multiple users cannot easily share the session once it is established, without some sort of external multiplexing scheme, such as running msfconsole in a screen session. While Metasploit Pro solves this issue to a certain extent, it is also limited by the number of users that can simultaneously  interact with shared sessions.

 2. Running a full msfconsole on a remote listener is resource intensive because it uses multiple threads per connection. It has a hard time scaling reliably to thousands of sessions, and even fewer on Windows platforms.

 3. The design requires either running different copies of msfconsole, or putting all of your eggs in one basket. It is difficult to distribute sessions across many endpoints and have a global view of them all.

The Metasploit Aggregator solves these problems by implementing an event-driven listener that stands between msfconsole and Meterpreter. It can scale to thousands of connections, but only needs to make a single connection with Metasploit Framework to manage them all.  Sessions can be shared between multiple users without any changes to the Meterpreter session
Itself, such as by modifying the session transport configuration. The redirection of a session occurs behind the scenes on the control channel between Metasploit Aggregator and msfconsole.

## Glossary

Metasploit Aggregator introduces a few new concepts.

* A **‘parked’** session is one that is terminated entirely by Metasploit Aggregator. This means that the minimal interaction with the session to simply keep it alive is handled by the aggregator automatically. A user can attach to a session at any time in order to interact with it.

* A **‘cable’** is a listening port that the aggregator opens to accept new connections from Meterpreter. This is analogous to starting a handler on msfconsole.

* The **‘default forward’** address is the location of a msfconsole instance that serves as a helper for Metasploit Aggregator. Metasploit Aggregator currently does not know how to handle staged sessions, request session details, or how to deal with AutoRun scripts. The default forward is where a session connecting to a cable is redirected on initial connection. The connection is enumerated for details of the target and continues to communicates with the default forward until requested specifically by another console or parked by request of the default forward.

* A **‘forwarded’** session is one that terminates at the aggregator, but is then proxied to a msfconsole instance. The session is forwarded over a control channel connection to the aggregator. When you are done interacting with a session, it can be moved back to a ‘parked’ state for other users to use. Note: any user can steal a session if desired and forward it to a different msfconsole instance.

## Installing
Standalone installation: ```gem install metasploit-aggregator```.

## Usage

To use Metasploit Aggregator, first start an instance of the aggregator itself. This is automatically packaged with Metasploit Framework, or can be installed standalone by running `gem install metasploit-aggregator`. The aggregator binary is called `metasploit-aggregator`, and listens on address 127.0.0.1, port 2447. Because the aggregator does not provide encryption or authentication by itself, to connect to a remote instance, we suggest using SSH port forwarding or some other tunneling technology to reach a remote aggregator.

<insert screenshot here>

Next, start a msfconsole instance and load the aggregator plugin. This will allow you to interact with the remote aggregator. This is also required to setup the default forward msfconsole instance. Setup the msfconsole instance to be the default forward. This instance will see all connections when they first arrive.

<insert screenshot here>

Startup a new cable to begin listening for Meterpreter sessions from the aggregator. You can optionally specify an SSL certificate for it to serve over HTTPS as well. You can verify that the cable is listening with the `aggregator_cables` command. This will also start a new handler automatically on the default forward instance of msfconsole to handle new sessions as they arrive.

<insert screenshot here>

Now, point a Meterpreter session at the cable address and port. You should see a new session on the default forward console. You can now park this session with the aggregator_session_park command.

<insert screenshot here>

To view all available sessions, use the aggregator_sessions command:

<insert screenshot here>

To forward an available session to your console, use the aggregator_session_forward command:

<insert screenshot here>

Finally, to disconnect from the aggregator, use the aggregator_disconnect command:

<insert screenshot here>

During disconnect, the console will park any sessions explicitly requested by the user.  If the console is registered as the “default forward” any sessions that have not been specifically requested will park, however the next console that registers as the default forward will be passed these passively parked sessions.

## Contributing
[Contributing](https://github.com/rapid7/metasploit-aggregator/blob/master/CONTRIBUTING.md).

Expanding protobuf service use
```grpc_tools_ruby_protoc -I ../protos --ruby_out=lib --grpc_out=lib ../protos/metasploit/aggregator/*```

