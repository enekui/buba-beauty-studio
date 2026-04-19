################################################################################
# AWS Budgets — alerta de coste mensual
#
# Se crea solo si var.budget_alert_email viene informado. El umbral por
# defecto son 5 USD/mes; con el uso previsto (~1-2 $/mes) cualquier
# disparo es señal de algo raro.
################################################################################

resource "aws_budgets_budget" "monthly" {
  count = var.budget_alert_email != "" ? 1 : 0

  name              = "${local.name_prefix}-monthly"
  budget_type       = "COST"
  limit_amount      = var.budget_monthly_usd
  limit_unit        = "USD"
  time_period_start = "2026-01-01_00:00"
  time_unit         = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Module$aws-email",
    ]
  }

  # Aviso en el 80% del umbral (actual real)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Aviso en el 100% del umbral (forecast)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
