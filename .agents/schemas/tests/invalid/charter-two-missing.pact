<?xml version="1.0" encoding="UTF-8"?>
<org:charter xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
             version="1.0">
  <persona name="Coordinator"/>
  <org:position class="coordinator" domain="delegation"/>
  <objective>Draft the delegation revamp files in staging.  Own the PACT core, the profile, and the lint first.</objective>
  <org:milestones>
    <org:milestone id="m1">PACT core, profile, and lint pass their tests.</org:milestone>
    <org:milestone id="m2">Class files and skills drafted in staging.</org:milestone>
  </org:milestones>
  <org:model band="sonnet" effort="high"/>
  <constraints>
    <constraint priority="critical" required="true">Write only in the staging root.</constraint>
    <constraint priority="normal">Name a model and an effort in every dispatch.</constraint>
  </constraints>
</org:charter>
