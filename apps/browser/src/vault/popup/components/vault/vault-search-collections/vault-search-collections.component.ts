import { CommonModule } from "@angular/common";
import { Component, ChangeDetectionStrategy, inject, input } from "@angular/core";

import { JslibModule } from "@bitwarden/angular/jslib.module";
import { CollectionView } from "@bitwarden/common/admin-console/models/collections";
import {
  SectionComponent,
  SectionHeaderComponent,
  ItemModule,
  IconComponent,
  TypographyModule,
} from "@bitwarden/components";

import { VaultPopupItemsService } from "../../../services/vault-popup-items.service";

@Component({
  selector: "app-vault-search-collections",
  standalone: true,
  imports: [
    CommonModule,
    JslibModule,
    SectionComponent,
    SectionHeaderComponent,
    ItemModule,
    IconComponent,
    TypographyModule,
  ],
  templateUrl: "./vault-search-collections.component.html",
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class VaultSearchCollectionsComponent {
  readonly collections = input<CollectionView[]>([]);

  private readonly vaultPopupItemsService = inject(VaultPopupItemsService);

  openCollection(collection: CollectionView): void {
    this.vaultPopupItemsService.openCollection(collection);
  }
}
