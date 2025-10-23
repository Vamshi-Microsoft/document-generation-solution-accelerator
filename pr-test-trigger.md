# PR Workflow Test

This is a test file created to trigger the pull request workflow.

**Test Details:**
- Date: October 23, 2025
- Purpose: Testing the pull request trigger in deploy-Parameterized.yml workflow
- Expected outcome: Workflow should run with PR-specific configuration (WAF_ENABLED=false, EXP=false, etc.)

## What the workflow should do:
1. Trigger on PR to main branch
2. Set automatic configuration for PR triggers
3. Deploy resources to Azure
4. Run E2E tests
5. Clean up resources after testing

This file can be safely deleted after testing is complete.