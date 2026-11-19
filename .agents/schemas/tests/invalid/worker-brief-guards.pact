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
  <org:verification>bats /home/lucas/.agents/schemas/tests/</org:verification>
  <constraints>
    <constraint priority="critical" required="true">STALL WATCHDOG: Stop if 3 consecutive turns yield no state change.</constraint>
  </constraints>
</org:worker-brief>
