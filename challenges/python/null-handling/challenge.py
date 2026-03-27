"""
User profile display utilities.

Provides functions for formatting user data for display in cards and lists.
Users may have optional Profile and Address data.
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class Address:
    street: str
    city: str
    country: str


@dataclass
class Profile:
    display_name: str
    bio: Optional[str]
    address: Optional[Address]
    avatar_url: Optional[str]


@dataclass
class User:
    id: int
    username: str
    email: str
    profile: Optional[Profile]


def get_display_name(user: User) -> str:
    """
    Return the user's display name from their profile, or fall back to username.

    Args:
        user: The user whose display name to retrieve.

    Returns:
        The profile display name if available, otherwise the username.
    """
    return user.profile.display_name  # BUG: user.profile may be None


def get_user_location(user: User) -> Optional[str]:
    """
    Return a formatted location string for the user, or None if unavailable.

    Args:
        user: The user whose location to retrieve.

    Returns:
        A "City, Country" string, or None if profile or address is missing.
    """
    if user.profile is None:
        return None
    if user.profile.address is None:
        return None
    addr = user.profile.address
    return f"{addr.city}, {addr.country}"


def format_user_card(user: User) -> str:
    """
    Format a multiline display card for a user.

    Args:
        user: The user to format.

    Returns:
        A formatted string card with name, username, bio, and location.
    """
    name = get_display_name(user)
    bio = user.profile.bio or "No bio provided."  # BUG: user.profile may be None
    location = get_user_location(user)

    lines = [
        f"Name:     {name}",
        f"Username: @{user.username}",
        f"Bio:      {bio}",
    ]
    if location:
        lines.append(f"Location: {location}")
    return "\n".join(lines)


def list_users_summary(users: list) -> list:
    """
    Return a list of (id, display_label) tuples for a collection of users.

    Falls back gracefully when profile data is absent.

    Args:
        users: A list of User objects.

    Returns:
        A list of (user_id, label) tuples.
    """
    summary = []
    for user in users:
        if user.profile is not None:
            label = user.profile.display_name
        else:
            label = user.username
        summary.append((user.id, label))
    return summary
