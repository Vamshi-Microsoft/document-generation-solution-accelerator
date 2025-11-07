# Deploy-Parameterized Workflow - Complete Analysis

## Overview

The `Deploy-Test-Cleanup (v2)` workflow is a comprehensive GitHub Actions pipeline designed to automate the deployment, testing, and cleanup of the Document Generation Solution Accelerator on Azure. The workflow supports multiple trigger types, configurable parameters, and intelligent job orchestration.

---

## Workflow Triggers

The workflow can be triggered in four different ways:

### 1. Pull Request Trigger
```yaml
pull_request:
  branches:
    - main
```
- **When**: Automatically runs when a PR is created or updated targeting the `main` branch
- **Purpose**: Validates PR changes before merging
- **Configuration**: Uses Non-WAF + Non-EXP configuration (forced)
- **Docker Image**: Uses existing branch-specific image
- **Cleanup**: Resources are automatically cleaned up after tests

### 2. Workflow Run Trigger
```yaml
workflow_run:
  workflows: ["Build Docker and Optional Push"]
  types:
    - completed
  branches:
    - main
    - dev
    - demo
```
- **When**: Runs after the "Build Docker and Optional Push" workflow completes
- **Purpose**: Deploy newly built Docker images
- **Configuration**: Uses Non-WAF + Non-EXP configuration (forced)
- **Docker Image**: Uses branch-specific image (latest_waf for main, dev for dev, demo for demo)
- **Cleanup**: Resources are automatically cleaned up after tests

### 3. Manual Dispatch (workflow_dispatch)
```yaml
workflow_dispatch:
  inputs:
    azure_location: [choice dropdown]
    resource_group_name: [optional string]
    waf_enabled: [boolean]
    EXP: [boolean]
    build_docker_image: [boolean]
    run_e2e_tests: [boolean]
    cleanup_resources: [boolean]
    AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID: [optional string]
    AZURE_EXISTING_AI_PROJECT_RESOURCE_ID: [optional string]
    existing_webapp_url: [optional string]
```
- **When**: Manually triggered by users through GitHub Actions UI
- **Purpose**: Custom deployments with full parameter control
- **Configuration**: User-defined (can enable WAF, EXP, etc.)
- **Docker Image**: User choice (use existing or build new)
- **Cleanup**: User-defined (default: enabled)

### 4. Scheduled Trigger
```yaml
schedule:
  - cron: '0 9,21 * * *'
```
- **When**: Runs automatically at 9:00 AM and 9:00 PM GMT daily
- **Purpose**: Regular validation and testing
- **Configuration**: Uses Non-WAF + Non-EXP configuration (forced)
- **Docker Image**: Uses latest_waf (main branch default)
- **Cleanup**: Resources are automatically cleaned up after tests

---

## Workflow Input Parameters

### Manual Dispatch Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `azure_location` | Choice | No | `australiaeast` | Azure region for infrastructure deployment. Options: australiaeast, centralus, eastasia, eastus2, japaneast, northeurope, southeastasia, uksouth, eastus |
| `resource_group_name` | String | No | Empty | Custom resource group name. If empty, auto-generates unique name |
| `waf_enabled` | Boolean | No | `false` | Enable Web Application Firewall configuration |
| `EXP` | Boolean | No | `false` | Enable EXP (Experience) configuration for reusing existing Log Analytics and AI Project |
| `build_docker_image` | Boolean | No | `false` | Build and push new Docker image with unique tag |
| `run_e2e_tests` | Boolean | No | `true` | Execute end-to-end tests after deployment |
| `cleanup_resources` | Boolean | No | `false` | Delete all deployed resources after completion |
| `AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID` | String | No | Empty | Existing Log Analytics Workspace ID (requires EXP=true) |
| `AZURE_EXISTING_AI_PROJECT_RESOURCE_ID` | String | No | Empty | Existing AI Project Resource ID (requires EXP=true) |
| `existing_webapp_url` | String | No | Empty | Test against existing webapp without deploying new resources |

### Auto-Configured Parameters

For automatic triggers (pull_request, workflow_run, schedule), the following parameters are **force-configured**:

```yaml
WAF_ENABLED: false
EXP: false
CLEANUP_RESOURCES: true
RUN_E2E_TESTS: true
BUILD_DOCKER_IMAGE: false
```

---

## Environment Variables

### Global Environment Variables

```yaml
GPT_MIN_CAPACITY: 150
TEXT_EMBEDDING_MIN_CAPACITY: 80
BRANCH_NAME: ${{ github.event.workflow_run.head_branch || github.head_ref || github.ref_name }}
```

### Dynamic Environment Variables

These are set based on trigger type and user inputs:

- `WAF_ENABLED`: Web Application Firewall configuration toggle
- `EXP`: Experience mode for reusing existing Azure resources
- `CLEANUP_RESOURCES`: Controls whether to delete resources after execution
- `RUN_E2E_TESTS`: Controls test execution
- `BUILD_DOCKER_IMAGE`: Controls Docker image building
- `AZURE_LOCATION`: Azure region for infrastructure
- `AZURE_ENV_OPENAI_LOCATION`: Azure region for OpenAI resources (determined by quota check)

---

## Job Architecture

The workflow consists of 5 jobs executed in the following order:

```
docker-build (conditional)
       ↓
    deploy (conditional)
       ↓
   e2e-test (conditional)
       ↓
cleanup-deployment (conditional)
       ↓
send-notification (always)
```

---

## Job 1: docker-build

### Purpose
Builds and pushes a custom Docker image to Azure Container Registry.

### Execution Conditions

| Trigger Type | Build Checkbox | Executes? | Image Used |
|--------------|----------------|-----------|------------|
| Pull Request | N/A | ❌ No | Branch image |
| Schedule | N/A | ❌ No | latest_waf |
| Workflow Run | N/A | ❌ No | Branch image |
| Manual | ✅ Checked | ✅ Yes | Custom unique tag |
| Manual | ❌ Unchecked | ❌ No | Branch image |

**Condition Code:**
```yaml
if: github.event_name == 'workflow_dispatch' && github.event.inputs.build_docker_image == 'true'
```

### Steps

1. **Checkout Code**: Retrieves repository code
2. **Generate Unique Docker Image Tag**: Creates tag format: `{branch}-{timestamp}-{run_id}`
   - Example: `main-20250107-143025-12345678`
3. **Set up Docker Buildx**: Configures Docker build environment
4. **Log in to Azure Container Registry**: Authenticates using secrets
5. **Build and Push Docker Image**: Builds from `./src/WebApp.Dockerfile` and pushes with tags:
   - Primary: `webapp:{IMAGE_TAG}`
   - Secondary: `webapp:{IMAGE_TAG}_{run_number}`
6. **Verify Docker Image Build**: Confirms successful build
7. **Generate Docker Build Summary**: Creates job summary in GitHub UI

### Outputs

- `IMAGE_TAG`: Unique Docker image tag (used by deploy job)

---

## Job 2: deploy

### Purpose
Deploys the Document Generation solution to Azure using Azure Developer CLI (azd).

### Execution Conditions

| Trigger Type | Existing URL | Executes? | Purpose |
|--------------|--------------|-----------|---------|
| Pull Request | N/A | ✅ Yes | Test PR changes |
| Schedule | N/A | ✅ Yes | Regular validation |
| Workflow Run | N/A | ✅ Yes | Deploy after build |
| Manual | Empty/None | ✅ Yes | Fresh deployment |
| Manual | Provided URL | ❌ No | Test existing only |

**Condition Code:**
```yaml
if: always() && (github.event_name != 'workflow_dispatch' || github.event.inputs.existing_webapp_url == '' || github.event.inputs.existing_webapp_url == null)
```

**Dependencies:** Waits for `docker-build` (uses `always()` so runs even if docker-build skips)

### Key Steps

#### 1. Display Workflow Configuration
Shows current configuration including trigger type, branch, and all parameter values.

#### 2. Validate and Auto-Configure EXP
**Auto-enables EXP if:**
- User provides `AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID` OR `AZURE_EXISTING_AI_PROJECT_RESOURCE_ID`
- But `EXP` checkbox is not explicitly checked

```yaml
if [[ -n "${{ github.event.inputs.AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID }}" ]] || [[ -n "${{ github.event.inputs.AZURE_EXISTING_AI_PROJECT_RESOURCE_ID }}" ]]; then
  echo "EXP=true" >> $GITHUB_ENV
fi
```

#### 3. Run Quota Check
Executes `scripts/checkquota.sh` to verify Azure OpenAI quota availability:
- Checks GPT capacity (min: 150)
- Checks Text Embedding capacity (min: 80)
- Tests regions: defined in `${{ vars.AZURE_REGIONS }}`
- **Outputs**: `VALID_REGION` (region with sufficient quota)
- **Failure Handling**: Sets `QUOTA_FAILED=true` and fails pipeline if no region has quota

#### 4. Set Deployment Region
Determines Azure regions:
- **AZURE_ENV_OPENAI_LOCATION**: Always from quota check result (`$VALID_REGION`)
- **AZURE_LOCATION**: 
  - Manual dispatch: User-selected location OR quota check result
  - Auto triggers: Quota check result

#### 5. Generate Resource Group Name
```yaml
# If provided by user:
RESOURCE_GROUP_NAME="${{ github.event.inputs.resource_group_name }}"

# If not provided (auto-generate):
RESOURCE_GROUP_NAME="arg-docgen-{SHORT_UUID}"
```

#### 6. Check and Create Resource Group
- Checks if resource group exists using `az group exists`
- Creates new resource group if it doesn't exist
- Reuses existing resource group if found

#### 7. Generate Unique Solution Prefix
Creates prefix for Azure resources:
```
SOLUTION_PREFIX="psldg{timestamp_last_6_digits}"
Example: psldg345678
```

#### 8. Determine Docker Image Tag

**Logic Flow:**

```yaml
if BUILD_DOCKER_IMAGE == true:
  IMAGE_TAG = {docker-build.outputs.IMAGE_TAG}  # Custom unique tag
else:
  if BRANCH == "main":
    IMAGE_TAG = "latest_waf"
  elif BRANCH == "dev":
    IMAGE_TAG = "dev"
  elif BRANCH == "demo":
    IMAGE_TAG = "demo"
  else:
    IMAGE_TAG = "latest_waf"  # Default fallback
```

#### 9. Configure Parameters Based on WAF Setting

```yaml
if WAF_ENABLED == true:
  # Copy WAF parameters file
  cp infra/main.waf.parameters.json infra/main.parameters.json
else:
  # Use default non-WAF parameters
  # (original main.parameters.json)
```

#### 10. Deploy using azd up

**Deployment Process:**
1. Create azd environment with generated name
2. Set environment variables:
   ```
   AZURE_SUBSCRIPTION_ID
   AZURE_ENV_OPENAI_LOCATION
   AZURE_LOCATION
   AZURE_RESOURCE_GROUP
   AZURE_ENV_IMAGETAG
   AZURE_DEV_COLLECT_TELEMETRY=no
   ```
3. **If EXP enabled**, set additional variables:
   ```
   AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID
   AZURE_EXISTING_AI_PROJECT_RESOURCE_ID
   ```
4. **If building Docker**, set ACR name:
   ```
   AZURE_ENV_ACR_NAME={extracted_from_login_server}
   ```
5. Execute `azd up --no-prompt`
6. Extract deployment outputs (webapp URL, resource IDs, etc.)

#### 11. Run Post-Deployment Script
Executes `./infra/scripts/process_sample_data.sh` to:
- Upload sample data to storage
- Configure Cosmos DB access
- Create AI Search indexes
- Set up initial configuration

#### 12. Generate Deploy Job Summary
Creates detailed summary in GitHub UI with:
- Job status
- Environment name
- Resource group
- Azure regions
- Docker image tag
- Configuration (WAF/EXP status)
- Web App URL

### Outputs

- `RESOURCE_GROUP_NAME`: Name of deployed resource group
- `WEBAPP_URL`: URL of deployed web application
- `ENV_NAME`: Unique environment name
- `AZURE_LOCATION`: Infrastructure deployment region
- `AZURE_ENV_OPENAI_LOCATION`: OpenAI deployment region
- `IMAGE_TAG`: Docker image tag used
- `QUOTA_FAILED`: Flag indicating quota check failure

---

## Job 3: e2e-test

### Purpose
Executes end-to-end tests against the deployed or existing web application.

### Execution Conditions

| Deploy Result | Existing URL | Test Checkbox | Executes? | Test Target |
|---------------|--------------|---------------|-----------|-------------|
| Success | N/A | Auto/✅/Default | ✅ Yes | Deployed URL |
| Success | Provided | Auto/✅/Default | ✅ Yes | Existing URL |
| Failed | Provided | Auto/✅/Default | ✅ Yes | Existing URL |
| Failed | N/A | Any | ❌ No | No URL |
| Success | N/A | ❌ Unchecked | ❌ No | Tests disabled |
| Success | Provided | ❌ Unchecked | ❌ No | Tests disabled |

**Condition Code:**
```yaml
if: always() && 
    ((needs.deploy.result == 'success' && needs.deploy.outputs.WEBAPP_URL != '') || 
     (github.event.inputs.existing_webapp_url != '' && github.event.inputs.existing_webapp_url != null)) && 
    (github.event_name != 'workflow_dispatch' || 
     github.event.inputs.run_e2e_tests == 'true' || 
     github.event.inputs.run_e2e_tests == null)
```

**Dependencies:** Waits for `docker-build` and `deploy` jobs

### Implementation

This job uses a reusable workflow:
```yaml
uses: ./.github/workflows/test-automation.yml
with:
  DOCGEN_URL: ${{ github.event.inputs.existing_webapp_url || needs.deploy.outputs.WEBAPP_URL }}
secrets: inherit
```

**URL Priority:**
1. If `existing_webapp_url` is provided → use it
2. Otherwise → use deployed `WEBAPP_URL`

### Outputs

- `TEST_SUCCESS`: Boolean indicating test success/failure
- `TEST_REPORT_URL`: URL to test execution report

---

## Job 4: cleanup-deployment

### Purpose
Deletes deployed Azure resources and custom Docker images after testing completes.

### Execution Conditions

| Deploy Result | Resource Group | Existing URL | Cleanup Checkbox | Executes? | Actions |
|---------------|----------------|--------------|------------------|-----------|---------|
| Success | Created | N/A | Auto/✅/Default | ✅ Yes | Delete RG + ACR |
| Success | Created | N/A | ❌ Unchecked | ❌ No | Keep resources |
| Success | Created | Provided | Any | ❌ No | No new resources |
| Failed | N/A | Any | Any | ❌ No | Nothing to clean |
| Success | None | Any | Any | ❌ No | No resources |

**Condition Code:**
```yaml
if: always() && 
    needs.deploy.result == 'success' && 
    needs.deploy.outputs.RESOURCE_GROUP_NAME != '' && 
    github.event.inputs.existing_webapp_url == '' && 
    (github.event_name != 'workflow_dispatch' || 
     github.event.inputs.cleanup_resources == 'true' || 
     github.event.inputs.cleanup_resources == null)
```

**Dependencies:** Waits for `docker-build`, `deploy`, and `e2e-test` jobs

### Steps

1. **Checkout Code**: Retrieves repository code
2. **Setup Azure Developer CLI**: Installs azd
3. **Login to Azure**: Authenticates with service principal
4. **Setup Azure CLI for Docker cleanup**: Installs and configures Azure CLI
5. **Delete Docker Images from ACR**:
   - **Only deletes custom images** (not standard branch images)
   - Preserves: `latest_waf`, `dev`, `demo` tags
   - Deletes: Custom timestamp-based tags from docker-build job
   ```yaml
   if IMAGE_TAG not in ["latest_waf", "dev", "demo"]:
     delete ACR image
   ```
6. **Select Environment and Delete deployment**:
   - Selects or recreates azd environment
   - Executes `azd down --purge --force --no-prompt`
   - Deletes entire resource group and all contained resources
7. **Logout from Azure**: Cleans up authentication
8. **Generate Cleanup Job Summary**: Creates summary in GitHub UI

---

## Job 5: send-notification

### Purpose
Sends email notifications about workflow execution results via Azure Logic App.

### Execution Conditions

**Always runs** (`if: always()`) to ensure notifications are sent regardless of job outcomes.

**Dependencies:** Waits for `docker-build`, `deploy`, and `e2e-test` jobs

### Notification Scenarios

#### 1. Quota Failure Notification
**Condition:** `needs.deploy.result == 'failure' && needs.deploy.outputs.QUOTA_FAILED == 'true'`

**Email Contains:**
- Quota check failure message
- Required GPT capacity (150)
- Required Text Embedding capacity (80)
- Checked regions list
- Run URL for troubleshooting

**Subject:** `DocGen Pipeline - Failed (Insufficient Quota)`

---

#### 2. Deployment Failure Notification
**Condition:** `needs.deploy.result == 'failure' && needs.deploy.outputs.QUOTA_FAILED != 'true'`

**Email Contains:**
- Deployment failure message
- Resource group name
- WAF/EXP configuration
- Run URL for investigation

**Subject:** `DocGen Pipeline - Failed`

---

#### 3. Success Notification (Deployment Only)
**Condition:** `needs.deploy.result == 'success' && needs.e2e-test.result == 'skipped'`

**Email Contains:**
- Deployment success message
- Resource group name
- Web App URL
- E2E tests status (skipped)
- WAF/EXP configuration
- Run URL

**Subject:** `DocGen Pipeline - Deployment Success`

---

#### 4. Success Notification (Deployment + Tests)
**Condition:** `needs.deploy.result == 'success' && needs.e2e-test.outputs.TEST_SUCCESS == 'true'`

**Email Contains:**
- Complete success message
- Resource group name
- Web App URL
- E2E tests status (passed)
- Test report URL
- WAF/EXP configuration
- Run URL

**Subject:** `DocGen Pipeline - Test Automation - Success`

---

#### 5. Test Failure Notification
**Condition:** `needs.deploy.result == 'success' && needs.e2e-test.result != 'skipped' && needs.e2e-test.outputs.TEST_SUCCESS != 'true'`

**Email Contains:**
- Test failure message
- Resource group name
- Web App URL
- Deployment status (success)
- E2E tests status (failed)
- Test report URL
- Run URL

**Subject:** `DocGen Pipeline - Test Automation - Failed`

---

#### 6. Existing URL Success Notification
**Condition:** `needs.deploy.result == 'skipped' && github.event.inputs.existing_webapp_url != '' && needs.e2e-test.result == 'success'`

**Email Contains:**
- Test success message for existing webapp
- Existing webapp URL
- Test report URL
- Deployment status (skipped)
- Run URL

**Subject:** `DocGen Pipeline - Test Automation Passed (Existing URL)`

---

#### 7. Existing URL Test Failure Notification
**Condition:** `needs.deploy.result == 'skipped' && github.event.inputs.existing_webapp_url != '' && needs.e2e-test.result == 'failure'`

**Email Contains:**
- Test failure message for existing webapp
- Existing webapp URL
- Test report URL
- Deployment status (skipped)
- Run URL

**Subject:** `DocGen Pipeline - Test Automation Failed (Existing URL)`

---

## Configuration Scenarios

### Scenario 1: Non-WAF + Non-EXP (Default for Auto Triggers)
```yaml
WAF_ENABLED: false
EXP: false
```
- Uses default `main.parameters.json`
- Creates new Log Analytics workspace
- Creates new AI Project
- Standard deployment without WAF

### Scenario 2: WAF + Non-EXP
```yaml
WAF_ENABLED: true
EXP: false
```
- Uses `main.waf.parameters.json`
- Creates new Log Analytics workspace
- Creates new AI Project
- Deployment with Web Application Firewall

### Scenario 3: Non-WAF + EXP
```yaml
WAF_ENABLED: false
EXP: true
AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID: "provided"
AZURE_EXISTING_AI_PROJECT_RESOURCE_ID: "provided"
```
- Uses default `main.parameters.json`
- Reuses existing Log Analytics workspace
- Reuses existing AI Project
- Standard deployment without WAF

### Scenario 4: WAF + EXP
```yaml
WAF_ENABLED: true
EXP: true
AZURE_ENV_LOG_ANALYTICS_WORKSPACE_ID: "provided"
AZURE_EXISTING_AI_PROJECT_RESOURCE_ID: "provided"
```
- Uses `main.waf.parameters.json`
- Reuses existing Log Analytics workspace
- Reuses existing AI Project
- Deployment with Web Application Firewall

---

## Workflow Execution Examples

### Example 1: Pull Request Trigger
```
Trigger: PR created targeting main branch
Branch: feature-branch

Flow:
1. docker-build: ❌ SKIPPED
2. deploy: ✅ RUNS
   - Image: feature-branch tag (or latest_waf fallback)
   - Config: Non-WAF + Non-EXP
   - Quota check: Determines best region
3. e2e-test: ✅ RUNS
   - Target: Deployed webapp URL
4. cleanup-deployment: ✅ RUNS
   - Deletes: Resource group
   - Preserves: Standard Docker images
5. send-notification: ✅ RUNS
   - Sends success/failure email
```

### Example 2: Manual Dispatch with Custom Docker Build
```
Trigger: Manual dispatch
Inputs:
  - build_docker_image: true
  - waf_enabled: true
  - cleanup_resources: false

Flow:
1. docker-build: ✅ RUNS
   - Builds: main-20250107-143025-12345678
2. deploy: ✅ RUNS
   - Image: main-20250107-143025-12345678
   - Config: WAF + Non-EXP
   - Creates resource group
3. e2e-test: ✅ RUNS
   - Target: Deployed webapp URL
4. cleanup-deployment: ❌ SKIPPED (cleanup_resources=false)
5. send-notification: ✅ RUNS
   - Sends success email
   - Resources remain in Azure
```

### Example 3: Manual Dispatch with Existing URL
```
Trigger: Manual dispatch
Inputs:
  - existing_webapp_url: "https://existing-app.azurewebsites.net"
  - run_e2e_tests: true

Flow:
1. docker-build: ❌ SKIPPED
2. deploy: ❌ SKIPPED (existing URL provided)
3. e2e-test: ✅ RUNS
   - Target: https://existing-app.azurewebsites.net
4. cleanup-deployment: ❌ SKIPPED (no deployment)
5. send-notification: ✅ RUNS
   - Sends test results for existing URL
```

### Example 4: Scheduled Run
```
Trigger: Cron schedule (9:00 AM GMT)
Branch: main

Flow:
1. docker-build: ❌ SKIPPED
2. deploy: ✅ RUNS
   - Image: latest_waf
   - Config: Non-WAF + Non-EXP
   - Quota check: Determines best region
3. e2e-test: ✅ RUNS
   - Target: Deployed webapp URL
4. cleanup-deployment: ✅ RUNS
   - Deletes: Resource group
   - Preserves: latest_waf image
5. send-notification: ✅ RUNS
   - Sends regular validation results
```

---

## Resource Naming Conventions

### Generated Names

| Resource | Format | Example |
|----------|--------|---------|
| Resource Group (auto) | `arg-docgen-{uuid}` | `arg-docgen-a1b2c3d4` |
| Resource Group (manual) | User-provided | `my-custom-rg` |
| Environment Name | `pslc{timestamp}` | `pslc345678` |
| Solution Prefix | `psldg{timestamp}` | `psldg345678` |
| Docker Image Tag (custom) | `{branch}-{timestamp}-{run_id}` | `main-20250107-143025-12345678` |
| Docker Image Tag (branch) | `latest_waf` / `dev` / `demo` | `latest_waf` |

---

## Security Configuration

### Secrets Required

| Secret | Purpose |
|--------|---------|
| `AZURE_CLIENT_ID` | Service principal authentication |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_CLIENT_SECRET` | Service principal password |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription |
| `ACR_TEST_LOGIN_SERVER` | Container registry server URL |
| `ACR_TEST_USERNAME` | Container registry username |
| `ACR_TEST_PASSWORD` | Container registry password |
| `LOGIC_APP_URL` | Email notification endpoint |
| `EXP_LOG_ANALYTICS_WORKSPACE_ID` | Default Log Analytics workspace (EXP) |
| `EXP_AI_PROJECT_RESOURCE_ID` | Default AI Project resource (EXP) |

### Variables Required

| Variable | Purpose |
|----------|---------|
| `AZURE_REGIONS` | Comma-separated list of Azure regions for quota check |

---

## Error Handling

### Quota Check Failure
- **Detection**: `scripts/checkquota.sh` returns non-zero exit code
- **Flag**: `QUOTA_FAILED=true`
- **Action**: Pipeline fails, notification sent with quota details
- **Recovery**: User must request quota increase or select different region

### Deployment Failure
- **Detection**: `azd up` command fails
- **Flag**: `needs.deploy.result == 'failure'`
- **Action**: Pipeline fails, notification sent with failure details
- **Cleanup**: No cleanup (resources may be partially created)
- **Recovery**: Manual investigation required

### Test Failure
- **Detection**: Test job returns failure status
- **Flag**: `needs.e2e-test.outputs.TEST_SUCCESS != 'true'`
- **Action**: Tests fail, but deployment remains (unless cleanup enabled)
- **Cleanup**: Cleanup runs if configured (deletes even on test failure)
- **Recovery**: Review test report, fix issues, re-run tests

### Docker Build Failure
- **Detection**: Docker build step fails
- **Action**: Pipeline fails, deploy job cannot proceed
- **Recovery**: Fix Dockerfile or source code issues

---

## Best Practices

### For Development
1. Use **pull request trigger** for PR validation
2. Enable **existing_webapp_url** to test against persistent dev environment
3. Keep **cleanup_resources=false** for debugging
4. Use **Non-WAF + Non-EXP** for faster iterations

### For Production
1. Use **workflow_run trigger** after successful Docker builds
2. Enable **WAF** for production deployments
3. Use **EXP** to reuse existing monitoring infrastructure
4. Enable **e2e tests** to validate before going live
5. Review notification emails for deployment confirmations

### For Testing
1. Use **manual dispatch** for full control
2. Enable **existing_webapp_url** to test without redeployment
3. Keep **run_e2e_tests=true** to validate functionality
4. Use **cleanup_resources=true** to avoid resource sprawl

### For Scheduled Runs
1. Monitor notification emails daily
2. Investigate failures promptly
3. Ensure quota availability in multiple regions
4. Keep **cleanup_resources=true** to avoid cost accumulation

---

## Troubleshooting

### Issue: Quota Check Always Fails
**Possible Causes:**
- Insufficient quota in all configured regions
- Network connectivity issues
- Invalid service principal permissions

**Solutions:**
- Request quota increase via Azure portal
- Add more regions to `AZURE_REGIONS` variable
- Verify service principal has quota read permissions

---

### Issue: Deployment Fails with "Resource Already Exists"
**Possible Causes:**
- Resource group name collision
- Previous cleanup didn't complete
- Manual resource creation conflicts

**Solutions:**
- Provide custom `resource_group_name` input
- Manually delete conflicting resources
- Wait for previous cleanup to complete

---

### Issue: E2E Tests Fail but Deployment Succeeds
**Possible Causes:**
- Application not fully initialized
- Test data issues
- Configuration mismatch

**Solutions:**
- Review test report URL in notification email
- Check webapp logs in Azure portal
- Verify post-deployment script execution
- Increase test timeout if needed

---

### Issue: Docker Image Not Found
**Possible Causes:**
- Image tag mismatch
- ACR authentication failure
- Image not built for branch

**Solutions:**
- Verify image exists in ACR
- Check ACR credentials in secrets
- Build image using `build_docker_image=true`
- Use existing branch image (latest_waf, dev, demo)

---

### Issue: Cleanup Job Fails
**Possible Causes:**
- Resources locked by Azure
- Permissions issues
- Network timeout

**Solutions:**
- Manual cleanup via Azure portal
- Check service principal permissions
- Verify no resource locks exist
- Re-run cleanup manually with azd CLI

---

## Monitoring and Observability

### GitHub Actions UI
- View real-time job execution progress
- Access job summaries with deployment details
- Download workflow run logs
- Monitor quota check results

### Email Notifications
- Receive immediate alerts on success/failure
- Access direct links to:
  - Deployed webapp URLs
  - Test report URLs
  - GitHub Actions run URLs
  - Azure resource groups

### Azure Portal
- Monitor deployed resources
- View application logs
- Check quota usage
- Review cost analysis

---

## Summary

The Deploy-Parameterized workflow is a sophisticated CI/CD pipeline that:

✅ **Supports multiple trigger types** for different use cases  
✅ **Performs intelligent quota checking** to ensure deployment success  
✅ **Allows flexible configuration** (WAF, EXP, custom parameters)  
✅ **Handles Docker image building** with unique tagging  
✅ **Deploys complete Azure infrastructure** using azd  
✅ **Executes comprehensive E2E tests** against deployed or existing apps  
✅ **Automatically cleans up resources** to prevent cost accumulation  
✅ **Sends detailed email notifications** for all execution outcomes  

This makes it suitable for development, testing, staging, and production deployment scenarios with appropriate safeguards and automation.
