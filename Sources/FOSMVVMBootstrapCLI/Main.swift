// Main.swift
import ArgumentParser
import FOSMVVMBootstrap

@main
struct FOSMVVMBootstrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fosmvvm-bootstrap",
        abstract: "Scaffold FOSMVVM projects the FOS-mvvm way.",
        version: Release.version,
        subcommands: [New.self]
    )
}
