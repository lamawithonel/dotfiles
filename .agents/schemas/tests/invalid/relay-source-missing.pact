<?xml version="1.0" encoding="UTF-8"?>
<org:relay xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
           version="1.0">
  <org:relayer>delegation-co</org:relayer>
  <org:source>no-such-freeze.pact</org:source>
  <org:quote>Reason: The registry file is being rewritten.
Scope: Every write to /home/lucas/.agents/model-benchmarks.json.
End: The executive sends a ruling that ends the freeze.
Lifter: agents-config-executive
Covers dispatch: false</org:quote>
  <org:additions>
    <org:added>This freeze does not cover dispatch.  Continue to dispatch workers that do not write the registry.</org:added>
  </org:additions>
</org:relay>
