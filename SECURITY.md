# Security

## Reporting a vulnerability

Please report security issues privately through GitHub's **Report a
vulnerability** flow rather than opening a public issue.

Include the affected version, macOS version, reproduction steps, and the
impact you observed. Do not include credentials, private meeting information,
or recorded audio.

## Project boundaries

Codex Micro Mic:

- reads live audio levels locally without recording audio;
- controls one named Core Audio input device;
- listens for lighting samples only on `127.0.0.1`;
- uses macOS Accessibility permission to send documented keyboard shortcuts;
- depends on a device library bundled inside Work Louder Input.

The project is an unofficial community integration and receives no security
support from OpenAI, Work Louder, RØDE, or the meeting-app vendors.
