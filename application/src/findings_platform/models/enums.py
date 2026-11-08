from enum import Enum

####### Finding #######


class Severity(Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"

    @property
    def rank(self) -> int:
        """Position from least to most severe; members are declared in that order."""
        return list(Severity).index(self)


class DetectionType(Enum):
    CLOUDTRAIL_LOGGING_STOPPED = "CLOUDTRAIL_LOGGING_STOPPED"
    ADMIN_ACCESS_GRANTED = "ADMIN_ACCESS_GRANTED"
    SG_OPEN_TO_WORLD = "SG_OPEN_TO_WORLD"


class Status(Enum):
    OPEN = "OPEN"
    RESOLVED = "RESOLVED"
    SUPPRESSED = "SUPPRESSED"


class SuppressionReason(Enum):
    ACCEPTED_RISK = "ACCEPTED_RISK"
    FALSE_POSITIVE = "FALSE_POSITIVE"
    INTENDED = "INTENDED"
