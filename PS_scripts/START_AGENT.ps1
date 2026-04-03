# START_AGENT.ps1
# Starts n8n + opens the UI.
Set-Location "F:\YouTubu_AI\n8n"
docker compose up -d
Start-Sleep -Seconds 2
Start-Process "http://localhost:5678"
Write-Host "n8n started: http://localhost:5678"
Write-Host "Workspace mounted at: F:\YouTubu_AI (inside container at /data)"
