# Deletes everything create.ps1 made: server (and its disk), firewall, role.
param(
    [string]$AwsProfile = "default",
    [string]$Region = "eu-north-1",
    [string]$AwsCli = "aws"
)
. "$PSScriptRoot\common.ps1"

$ids = Invoke-Aws ec2 describe-instances `
    --filters "Name=tag:Project,Values=$Name" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
    --query "Reservations[].Instances[].InstanceId" --output text
if ($ids) {
    $ids = @($ids -split "\s+" | Where-Object { $_ })
    Write-Host "Terminating server(s): $($ids -join ', ')"
    Invoke-Aws ec2 terminate-instances --instance-ids $ids | Out-Null
    Invoke-Aws ec2 wait instance-terminated --instance-ids $ids | Out-Null
}

$sg = Invoke-Aws ec2 describe-security-groups --filters "Name=group-name,Values=$Name-web" `
    --query "SecurityGroups[0].GroupId" --output text
if ($sg -and $sg -ne "None") {
    Write-Host "Deleting firewall $sg"
    Invoke-Aws ec2 delete-security-group --group-id $sg | Out-Null
}

if (Test-Aws iam get-instance-profile --instance-profile-name "$Name-server") {
    Write-Host "Deleting server role"
    Test-Aws iam remove-role-from-instance-profile --instance-profile-name "$Name-server" --role-name "$Name-server" | Out-Null
    Invoke-Aws iam delete-instance-profile --instance-profile-name "$Name-server" | Out-Null
}
if (Test-Aws iam get-role --role-name "$Name-server") {
    Invoke-Aws iam detach-role-policy --role-name "$Name-server" `
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore | Out-Null
    Invoke-Aws iam delete-role --role-name "$Name-server" | Out-Null
}
Write-Host "Done: nothing tagged Project=$Name is left running."
