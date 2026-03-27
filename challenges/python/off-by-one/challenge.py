"""
Pair finder utilities.

Provides functions for finding pairs of numbers that sum to a target value,
both in flat lists and in 2D matrices.
"""

from typing import List, Tuple


def find_pairs(numbers: List[int], target: int) -> List[Tuple[int, int]]:
    """
    Find all unique pairs in a list that sum to the target value.

    Args:
        numbers: A list of integers to search.
        target: The target sum for each pair.

    Returns:
        A list of (a, b) tuples where a + b == target and a <= b.
    """
    pairs: List[Tuple[int, int]] = []
    for i in range(len(numbers)):
        for j in range(i, len(numbers)):  # BUG: should be range(i + 1, ...)
            if numbers[i] + numbers[j] == target:
                pairs.append((numbers[i], numbers[j]))
    return pairs


def count_valid_pairs(numbers: List[int], target: int) -> int:
    """
    Count how many unique pairs in the list sum to the target.

    Args:
        numbers: A list of integers to search.
        target: The target sum for each pair.

    Returns:
        The number of valid pairs found.
    """
    return len(find_pairs(numbers, target))


def find_pairs_in_matrix(matrix: List[List[int]], target: int) -> List[Tuple[int, int]]:
    """
    Find all unique pairs across all rows of a 2D matrix that sum to the target.

    Each row is searched independently; pairs do not span across rows.

    Args:
        matrix: A 2D list of integers.
        target: The target sum for each pair.

    Returns:
        A flat list of all (a, b) pairs found across all rows.
    """
    results: List[Tuple[int, int]] = []
    for row in matrix:
        results.extend(find_pairs(row, target))
    return results
