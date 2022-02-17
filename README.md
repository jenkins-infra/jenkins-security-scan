# Jenkins Security Scan Action and Workflow

This repository contains the following GitHub actions and workflows:

* A reusable workflow `jenkins-security-scan`. See [jenkinsci/.github](https://github.com/jenkinsci/.github/tree/master/workflow-templates) for a workflow template that calls this workflow.
* The `jenkins-codeql` action that performs a scan using the [custom Jenkins CodeQL rules](https://github.com/jenkins-infra/jenkins-codeql).
* The `fetch-codeql` action that downloads a specific version of the [CodeQL CLI Binaries](https://github.com/github/codeql-cli-binaries).
