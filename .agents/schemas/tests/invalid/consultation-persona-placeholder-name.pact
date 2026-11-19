<?xml version="1.0" encoding="UTF-8"?>
<org:consultation xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
                  version="1.0">
  <persona name="{{writer}}"/>
  <org:position class="consultant" domain="delegation" specialty="pact"/>
  <org:creator>delegation-co</org:creator>
  <objective>Answer questions about the PACT schemas and their lint rules.</objective>
  <org:ends-when>The coordinator's named workers finish.</org:ends-when>
  <org:model band="opus" effort="xhigh"/>
  <org:onboarding digest="/home/lucas/.agents/schemas/pact-1.0.xsd"/>
</org:consultation>
