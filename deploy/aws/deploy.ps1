# Deploys (or rolls back to) a published image version through Systems Manager. No SSH.
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+$')][string]$Version,
    [string]$AwsProfile = "default",
    [string]$Region = "eu-north-1",
    [string]$AwsCli = "aws"
)
. "$PSScriptRoot\common.ps1"

$instanceId = Get-ServerInstanceId
$paramsFile = Join-Path ([IO.Path]::GetTempPath()) "$Name-deploy-params.json"
[IO.File]::WriteAllText($paramsFile, (@{ commands = @("/opt/app/deploy.sh $Version") } | ConvertTo-Json -Compress))

$commandId = Invoke-Aws ssm send-command --instance-ids $instanceId --document-name AWS-RunShellScript `
    --comment "Deploy $Version" --parameters "file://$paramsFile" --query Command.CommandId --output text
Remove-Item $paramsFile

& $AwsCli ssm wait command-executed --command-id $commandId --instance-id $instanceId --profile $AwsProfile --region $Region
Invoke-Aws ssm get-command-invocation --command-id $commandId --instance-id $instanceId `
    --query "[Status,StandardOutputContent,StandardErrorContent]" --output text

$ip = Invoke-Aws ec2 describe-instances --instance-ids $instanceId `
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text
Write-Host "/health: $(Wait-Health $ip | ConvertTo-Json -Compress)"
