from werkzeug.security import generate_password_hash, check_password_hash


def hash_password(password: str) -> str:
    """Hash password using Werkzeug's secure hashing (scrypt / pbkdf2)."""
    return generate_password_hash(password)


def check_password(password_hash: str, password: str) -> bool:
    """Verify password against stored hash."""
    if not password_hash or not password:
        return False
    return check_password_hash(password_hash, password)


def hash_pin(pin: str) -> str:
    """Hash 4-6 digit safety PIN."""
    return generate_password_hash(str(pin))


def check_pin(pin_hash: str, pin: str) -> bool:
    """Verify safety PIN against stored hash."""
    if not pin_hash or not pin:
        return False
    return check_password_hash(pin_hash, str(pin))
