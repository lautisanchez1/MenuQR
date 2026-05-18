"""Cognito CustomMessage trigger — branded transactional emails (plain text)."""

BRAND = "MenuQR"
CODE = "{####}"


def _footer() -> str:
    return (
        f"\n—\n"
        f"If you did not request this, you can ignore this email.\n"
        f"© {BRAND}"
    )


def handler(event, context):
    trigger = event.get("triggerSource", "")
    response = event.setdefault("response", {})

    if trigger == "CustomMessage_SignUp":
        response["emailSubject"] = f"Verify your {BRAND} account"
        response["emailMessage"] = (
            f"Welcome to {BRAND}!\n\n"
            f"Use this verification code to finish creating your account:\n\n"
            f"    {CODE}\n\n"
            f"The code expires in 24 hours."
            f"{_footer()}"
        )
    elif trigger == "CustomMessage_ResendCode":
        response["emailSubject"] = f"Your {BRAND} verification code"
        response["emailMessage"] = (
            f"Here is your new verification code:\n\n"
            f"    {CODE}\n\n"
            f"The code expires in 24 hours."
            f"{_footer()}"
        )
    elif trigger == "CustomMessage_ForgotPassword":
        response["emailSubject"] = f"Reset your {BRAND} password"
        response["emailMessage"] = (
            f"We received a request to reset your {BRAND} password.\n\n"
            f"Enter this code in the admin app to choose a new password:\n\n"
            f"    {CODE}\n\n"
            f"The code expires in 1 hour. If you did not ask for a reset, ignore this email."
            f"{_footer()}"
        )
    elif trigger == "CustomMessage_UpdateUserAttribute":
        response["emailSubject"] = f"Confirm your {BRAND} email change"
        response["emailMessage"] = (
            f"Confirm your new email address with this code:\n\n"
            f"    {CODE}\n\n"
            f"The code expires in 24 hours."
            f"{_footer()}"
        )

    return event
