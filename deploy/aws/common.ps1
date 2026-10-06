$ErrorActionPreference = "Stop"
$Name = "deployment-lab"

function Invoke-Aws {
    $out = & $AwsCli @args --profile $AwsProfile --region $Region
    if ($LASTEXITCODE -ne 0) { throw "aws $($args -join ' ') failed (exit code $LASTEXITCODE)" }
    $out
}

function Test-Aws {
    # Windows PowerShell turns redirected stderr into terminating errors under "Stop".
    $ErrorActionPreference = "Continue"
    & $AwsCli @args --profile $AwsProfile --region $Region 2>$null | Out-Null
    $LASTEXITCODE -eq 0
}

function Get-ServerInstanceId {
    $id = Invoke-Aws ec2 describe-instances `
        --filters "Name=tag:Project,Values=$Name" "Name=instance-state-name,Values=running" `
        --query "Reservations[0].Instances[0].InstanceId" --output text
    if ($id -eq "None" -or -not $id) { throw "No running $Name server found" }
    $id
}

function Wait-Health($ip) {
    for ($i = 0; $i -lt 30; $i++) {
        try { return Invoke-RestMethod "http://$ip/health" -TimeoutSec 5 } catch { Start-Sleep -Seconds 10 }
    }
    throw "No answer from http://$ip/health after 5 minutes"
}
