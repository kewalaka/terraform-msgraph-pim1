# Demo PIM MSGraph issue

## Step 1: Apply Configuration

Set required variables

```bash
export ARM_TENANT_ID="<REDACT>"
export ARM_CLIENT_ID="<REDACT>"
export ARM_SUBSCRIPTION_ID="<REDACT>"
# or use OIDC
export ARM_CLIENT_SECRET="<REDACT>"
```

```bash
terraform init
terraform apply -auto-approve
```

**Expected Output:**

```text
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Example Outputs:
group_id = "6770bd4a-8b87-45ad-87ab-337cc28098bf"
policy_id = "Group_6770bd4a-8b87-45ad-87ab-337cc28098bf_f5f8e4c0-6d44-4103-8e95-8aa954f7f0e1"
```

## Step 2: Verify Terraform State

```bash
terraform show -json | jq '.values.root_module.resources[] | select(.address == "msgraph_update_resource.enablement_rule") | .values.body.enabledRules'
```

**Output (what Terraform thinks it set):**

```json
["Justification", "Ticketing", "MultiFactorAuthentication"]
```

### Step 4: Check Actual API State

```powershell
Connect-MgGraph -Scopes 'RoleManagementPolicy.Read.AzureADGroup' -NoWelcome

$policyId = $(terraform output -raw policy_id)
$policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/policies/roleManagementPolicies/$policyId`?`$expand=rules"

# Check enablement rule
$enablementRule = $policy.rules | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }
Write-Host "Enabled Rules (API):" $enablementRule.enabledRules

# Check approval rule
$approvalRule = $policy.rules | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
Write-Host "Approval Required (API):" $approvalRule.setting.isApprovalRequired
Write-Host "Primary Approvers Count (API):" $approvalRule.setting.approvalStages[0].primaryApprovers.Count
```

**Output (actual API state):**

```text
Enabled Rules (API): Justification
Approval Required (API): False
Approver Count (API): 0
```

### Step 5: Observe Drift

```bash
terraform plan
```

**Output:**

```text
Terraform will perform the following actions:

  # msgraph_update_resource.approval_rule will be updated in-place
  ~ resource "msgraph_update_resource" "approval_rule" {
      ~ body = {
          ~ setting = {
              ~ isApprovalRequired = false -> true
              ~ approvalStages     = [
                  ~ {
                      ~ primaryApprovers = [] -> [{...}]
                    }
                ]
            }
        }
    }

  # msgraph_update_resource.enablement_rule will be updated in-place
  ~ resource "msgraph_update_resource" "enablement_rule" {
      ~ body = {
          ~ enabledRules = ["Justification"] -> ["Justification", "Ticketing", "MultiFactorAuthentication"]
        }
    }

Plan: 0 to add, 2 to change, 0 to destroy.
```
