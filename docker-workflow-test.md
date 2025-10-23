# Docker Workflow Test

This file is created to trigger the "Build Docker and Optional Push" workflow, which should then trigger the "Deploy-Test-Cleanup (Parameterized)" workflow via workflow_run.

**Chain of events expected:**
1. Push this file → triggers "Build Docker and Optional Push" 
2. "Build Docker and Optional Push" completes → triggers "Deploy-Test-Cleanup (Parameterized)"

Test timestamp: October 23, 2025