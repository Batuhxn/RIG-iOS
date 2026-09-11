import SwiftUI
import UIKit

/// The individual screen bodies `content(_:)` dispatches between, split into
/// its own file purely for the static audit's line cap — see the type's own
/// doc comment in `OutfitPhotoSessionView.swift`. `content(_:)` itself stays
/// in the main file, since it is the dispatcher that reads every piece of
/// state these screens are chosen from.
extension OutfitPhotoSessionView {
    var loadingScreen: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Opening your photo…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var processingScreen: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Separating the garment…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing the cropped garment")
    }

    func sourceScreen(_ image: UIImage) -> some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))
                .padding(.horizontal, RIGTheme.Spacing.m)
                .accessibilityHidden(true)

            Text(savedSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Add garment", action: beginCandidate)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Finish", action: finish)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
    }

    func croppingScreen(_ image: UIImage) -> some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            GarmentCropView(image: image, sourcePixelSize: sourcePixelSize, region: $draftRegion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, RIGTheme.Spacing.s)

            Text("Drag the box over one garment.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Preview crop", action: previewDraft)
                .buttonStyle(RIGPrimaryButtonStyle())
                .disabled(!draftRegion.isUsable)

                Button("Cancel", action: discard)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
    }

    func reviewScreen(_ result: GarmentImportResult) -> some View {
        Form {
            Section {
                GarmentImageView(
                    relativePath: result.cutoutRelativePath ?? result.originalRelativePath,
                    symbolName: fields.category.symbolName
                )
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

                if let message = result.backgroundRemovalMessage {
                    Text("\(message) The cropped photo will be used instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isCheckingForDuplicates {
                    HStack(spacing: RIGTheme.Spacing.s) {
                        ProgressView().controlSize(.small)
                        Text("Checking your wardrobe for anything similar…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GarmentMetadataForm(fields: $fields)

            Section {
                Button("Crop again", action: recrop)
                Button("Discard this garment", role: .destructive, action: discard)
            } footer: {
                Text("Garments you have already saved stay in your wardrobe.")
            }
        }
    }

    func candidateFailureScreen(_ message: String) -> some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Spacer(minLength: 0)
            RIGErrorBanner(message: message)
                .padding(.horizontal, RIGTheme.Spacing.m)
            Text("The rest of this photo is untouched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Crop again", action: recrop)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Discard this garment", action: discard)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func sourceFailureScreen(_ message: String) -> some View {
        RIGEmptyState(
            symbol: "exclamationmark.triangle",
            title: "That photo could not be opened",
            message: message,
            actionTitle: "Close",
            action: finish
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(session.resolvedCount > 0 ? "Done" : "Cancel", action: finish)
        }
        if session.active?.importResult != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: beginSave)
                    .disabled(!fields.isValid || isCheckingForDuplicates)
            }
        }
    }

    var savedSummary: String {
        switch session.resolvedCount {
        case 0:
            return "Nothing saved from this photo yet."
        default:
            if session.linkedCount == 0 {
                return session.savedCount == 1
                    ? "1 garment saved from this photo."
                    : "\(session.savedCount) garments saved from this photo."
            }
            if session.savedCount == 0 {
                return session.linkedCount == 1
                    ? "1 garment linked to your wardrobe from this photo."
                    : "\(session.linkedCount) garments linked to your wardrobe from this photo."
            }
            return "\(session.savedCount) new, \(session.linkedCount) linked to your wardrobe, from this photo."
        }
    }
}
