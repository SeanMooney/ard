#!/usr/bin/env python3
"""Focused tests for structured libvirt installation-media validation."""

import argparse
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


HELPER = (
    Path(__file__).parents[2] / "files" / "ard-libvirt-domain-identity"
)
LOADER = SourceFileLoader("ard_domain_identity", str(HELPER))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(MODULE)


class MediaPolicyTest(unittest.TestCase):
    def args(self, policy="absent"):
        return argparse.Namespace(
            domain="test",
            root_source="/disk",
            root_target="sda",
            root_bus="scsi",
            media_source="/expected.iso",
            media_target="sdb",
            media_policy=policy,
            interface=["52:54:00:00:00:01=test-net"],
        )

    def xml(self, source=""):
        return ET.fromstring(
            "<domain><name>test</name><devices>"
            '<disk device="disk"><source file="/disk"/>'
            '<target dev="sda" bus="scsi"/></disk>'
            f'<disk device="cdrom">{source}'
            '<target dev="sdb" bus="sata"/></disk>'
            '<interface><mac address="52:54:00:00:00:01"/>'
            '<source network="test-net"/></interface>'
            "</devices></domain>"
        )

    def test_absent_accepts_missing_source(self):
        MODULE.validate(self.args(), self.xml(), "test")

    def test_absent_accepts_index_only_empty_source(self):
        MODULE.validate(self.args(), self.xml('<source index="3"/>'), "test")

    def test_absent_rejects_backing_sources(self):
        sources = (
            '<source file="/wrong.iso"/>',
            '<source dev="/dev/sr0"/>',
            '<source protocol="https" name="image.iso"/>',
            '<source><host name="images.example.test"/></source>',
            '<source index="3" startupPolicy="optional"/>',
        )
        for source in sources:
            with self.subTest(source=source):
                with self.assertRaisesRegex(
                    ValueError, "installation media is still attached"
                ):
                    MODULE.validate(self.args(), self.xml(source), "test")

    def test_required_accepts_exact_file_source(self):
        MODULE.validate(
            self.args("required"),
            self.xml('<source file="/expected.iso"/>'),
            "test",
        )


if __name__ == "__main__":
    unittest.main()
