{...}: {
  services.logind.settings.Login.HandlePowerKey = "ignore";
  services.logind.settings.Login.HandleLidSwitch = "lock";
}
