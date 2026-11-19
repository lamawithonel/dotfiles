<?xml version="1.0" encoding="UTF-8"?>
<org:escalation xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
                version="1.0">
  <persona name="X">You write the way a field guide does: plain and exact.</persona>
  <org:from>delegation-co</org:from>
  <org:to>agents-config-executive</org:to>
  <org:problem>The design does not say which class may start a consultant for a standalone session.</org:problem>
  <org:request>Decide who may start it.</org:request>
  <org:options>
    <org:option>Only the user may start it.</org:option>
    <org:option>The standalone session may start it when the user directs it.</org:option>
  </org:options>
  <org:evidence>/home/lucas/.local/share/agents/research/delegation-revamp/design.md</org:evidence>
</org:escalation>
