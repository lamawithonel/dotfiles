<?xml version="1.0" encoding="UTF-8"?>
<org:worker-brief xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
                  version="1.0">
  <role name="schema-worker">You are a worker.  Your work package is the PACT lint script.</role>
  <objective>Write the lint script so that it exits 0 for a valid document and 1 for an invalid one.</objective>
  <context>Schemas: /home/lucas/.agents/schemas/.  Tests: /home/lucas/.agents/schemas/tests/.</context>
  <tasks>
    <task name="tests">
      <summary>Write the failing tests.</summary>
      <details>Cover each document type.  Run the tests and keep the red output.</details>
      <acceptance_criteria>
        <criterion>Each type has one invalid example that the lint rejects.</criterion>
      </acceptance_criteria>
    </task>
    <task name="script">
      <summary>Write the script that turns the tests green.</summary>
    </task>
  </tasks>
  <constraints>
    <constraint priority="critical" required="true">Write no file outside the staging root.</constraint>
  </constraints>
</org:worker-brief>
