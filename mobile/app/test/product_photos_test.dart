import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thy_app/core/media/photo_picker.dart';
import 'package:thy_app/features/products/data/product_models.dart';
import 'package:thy_app/features/products/presentation/product_photo.dart';

import 'fakes.dart';

PickedPhoto get _photo => PickedPhoto(bytes: tinyPng, filename: 'photo.png');

Future<void> openStockTab(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Stock')));
  await tester.pumpAndSettle();
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Circular list pictures that currently show a real photo (not the initial).
Finder get _avatarsWithPhoto =>
    find.byWidgetPredicate((w) => w is CircleAvatar && w.backgroundImage is MemoryImage);

void main() {
  late FakeProductsApi productsApi;

  setUp(() {
    productsApi = FakeProductsApi([
      testProduct(id: 'p1', name: 'Eau minérale 1.5L', stock: 10),
      testProduct(id: 'p2', name: 'Savon de toilette', stock: 5, imageKey: 'k-p2'),
    ])..images['p2'] = tinyPng;
  });

  Future<void> openNewProductForm(WidgetTester tester, FakePhotoPicker picker) async {
    await pumpAuthenticatedApp(tester, products: productsApi, photoPicker: picker);
    await openStockTab(tester);
    await tapAndSettle(tester, find.text('Produit'));
  }

  Future<void> chooseFromGallery(WidgetTester tester, {String button = 'Ajouter une photo'}) async {
    await tapAndSettle(tester, find.text(button));
    await tapAndSettle(tester, find.text('Choisir dans la galerie'));
  }

  Future<void> fillMinimalProduct(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Riz local');
    await tester.enterText(fields.at(2), '220 000');
  }

  Future<void> openEditFormOf(
    WidgetTester tester,
    String productName,
    FakePhotoPicker picker,
  ) async {
    await pumpAuthenticatedApp(tester, products: productsApi, photoPicker: picker);
    await openStockTab(tester);
    await tapAndSettle(tester, find.text(productName));
    await tapAndSettle(tester, find.byTooltip('Modifier'));
  }

  group('Product model', () {
    test('reads the photo key and knows whether there is a photo', () {
      final withPhoto = Product.fromJson({
        'id': 'p',
        'name': 'Savon',
        'purchasePrice': '1',
        'salePrice': '2',
        'currentStock': '3',
        'imageKey': 'biz/products/p/abc.png',
      });
      final without = Product.fromJson({
        'id': 'q',
        'name': 'Eau',
        'purchasePrice': '1',
        'salePrice': '2',
        'currentStock': '3',
        'imageKey': null,
      });

      expect(withPhoto.imageKey, 'biz/products/p/abc.png');
      expect(withPhoto.hasImage, isTrue);
      expect(without.hasImage, isFalse);
    });
  });

  group('New product form', () {
    testWidgets('a picked photo is only uploaded once the product is saved', (tester) async {
      final picker = FakePhotoPicker(_photo);
      await openNewProductForm(tester, picker);

      // Camera and gallery are both offered on a phone.
      await tapAndSettle(tester, find.text('Ajouter une photo'));
      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Choisir dans la galerie'), findsOneWidget);
      await tapAndSettle(tester, find.text('Choisir dans la galerie'));

      expect(picker.requested, [PhotoSource.gallery]);
      expect(find.text('Changer la photo'), findsOneWidget);
      expect(find.text('Retirer la photo'), findsOneWidget);
      expect(productsApi.uploads, isEmpty, reason: 'nothing is sent before the product exists');

      await fillMinimalProduct(tester);
      await tapAndSettle(tester, find.text('Ajouter le produit'));

      expect(productsApi.created.single.name, 'Riz local');
      final upload = productsApi.uploads.single;
      expect(upload.productId, 'new-1');
      expect(upload.size, tinyPng.length);
      expect(upload.filename, 'photo.png');
    });

    testWidgets('the camera can be chosen too', (tester) async {
      final picker = FakePhotoPicker(_photo);
      await openNewProductForm(tester, picker);

      await tapAndSettle(tester, find.text('Ajouter une photo'));
      await tapAndSettle(tester, find.text('Prendre une photo'));

      expect(picker.requested, [PhotoSource.camera]);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      await openNewProductForm(tester, FakePhotoPicker(null));

      await chooseFromGallery(tester);

      expect(find.text('Ajouter une photo'), findsOneWidget);
      expect(find.text('Retirer la photo'), findsNothing);
    });

    testWidgets('a photo over 2 MB is refused before anything is sent', (tester) async {
      final heavy = PickedPhoto(bytes: Uint8List(maxPhotoBytes + 1), filename: 'grosse.jpg');
      await openNewProductForm(tester, FakePhotoPicker(heavy));

      await chooseFromGallery(tester);

      expect(find.text('Photo trop lourde (2 Mo maximum).'), findsOneWidget);
      expect(find.text('Retirer la photo'), findsNothing);
    });

    testWidgets('a denied camera / gallery gets an explanation, not a crash', (tester) async {
      final picker = FakePhotoPicker()..error = Exception('permission denied');
      await openNewProductForm(tester, picker);

      await chooseFromGallery(tester);

      expect(find.textContaining("Impossible d'ouvrir la caméra ou la galerie"), findsOneWidget);
      expect(find.text('Ajouter une photo'), findsOneWidget);
    });

    testWidgets('a failing upload keeps the saved product and says so', (tester) async {
      productsApi.uploadError = 'Format de photo non pris en charge.';
      await openNewProductForm(tester, FakePhotoPicker(_photo));
      await chooseFromGallery(tester);
      await fillMinimalProduct(tester);

      await tapAndSettle(tester, find.text('Ajouter le produit'));

      expect(productsApi.created, hasLength(1));
      expect(productsApi.uploads, isEmpty);
      expect(
        find.textContaining("Produit enregistré, mais la photo n'a pas pu être envoyée"),
        findsOneWidget,
      );
      // Back on the list: the user is not stuck on the form.
      expect(find.text('Ajouter le produit'), findsNothing);
      expect(find.text('Riz local'), findsOneWidget);
    });

    testWidgets('a product without a photo is saved without any upload', (tester) async {
      await openNewProductForm(tester, FakePhotoPicker(_photo));
      await fillMinimalProduct(tester);

      await tapAndSettle(tester, find.text('Ajouter le produit'));

      expect(productsApi.created, hasLength(1));
      expect(productsApi.uploads, isEmpty);
      expect(productsApi.imageDeletions, isEmpty);
    });
  });

  group('Editing a product that has a photo', () {
    testWidgets('"Retirer la photo" deletes it when saving', (tester) async {
      await openEditFormOf(tester, 'Savon de toilette', FakePhotoPicker());

      expect(find.text('Changer la photo'), findsOneWidget);
      await tapAndSettle(tester, find.text('Retirer la photo'));
      expect(find.text('Ajouter une photo'), findsOneWidget);
      expect(productsApi.imageDeletions, isEmpty, reason: 'nothing changes until Enregistrer');

      await tapAndSettle(tester, find.text('Enregistrer'));

      expect(productsApi.updatedIds, ['p2']);
      expect(productsApi.imageDeletions, ['p2']);
      expect(productsApi.uploads, isEmpty);
    });

    testWidgets('choosing another photo replaces it', (tester) async {
      await openEditFormOf(tester, 'Savon de toilette', FakePhotoPicker(_photo));

      await chooseFromGallery(tester, button: 'Changer la photo');
      await tapAndSettle(tester, find.text('Enregistrer'));

      expect(productsApi.uploads.single.productId, 'p2');
      expect(productsApi.imageDeletions, isEmpty);
    });

    testWidgets('saving without touching the photo leaves it alone', (tester) async {
      await openEditFormOf(tester, 'Savon de toilette', FakePhotoPicker(_photo));

      await tapAndSettle(tester, find.text('Enregistrer'));

      expect(productsApi.updatedIds, ['p2']);
      expect(productsApi.uploads, isEmpty);
      expect(productsApi.imageDeletions, isEmpty);
    });
  });

  group('Showing photos', () {
    testWidgets('the Stock list shows the photo when there is one, the initial otherwise', (
      tester,
    ) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);

      expect(_avatarsWithPhoto, findsOneWidget);
      expect(find.text('E'), findsOneWidget, reason: 'no photo: the initial of "Eau minérale"');
      expect(find.text('S'), findsNothing, reason: 'photo shown instead of the initial');
      expect(productsApi.imageFetches, ['p2'], reason: 'only products with a photo are fetched');
    });

    testWidgets('the Caisse shows it too', (tester) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await tapAndSettle(
        tester,
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Caisse')),
      );

      expect(_avatarsWithPhoto, findsOneWidget);
      expect(find.text('E'), findsOneWidget);
    });

    testWidgets('the product page opens with its photo', (tester) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);
      await tapAndSettle(tester, find.text('Savon de toilette'));

      expect(find.byType(ProductPhoto), findsOneWidget);
    });

    testWidgets('the product page of a product without a photo has no photo block', (tester) async {
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);
      await tapAndSettle(tester, find.text('Eau minérale 1.5L'));

      expect(find.byType(ProductPhoto), findsNothing);
    });

    testWidgets('a photo that cannot be loaded falls back to the initial', (tester) async {
      productsApi.images.clear(); // the server answers 404 for p2
      await pumpAuthenticatedApp(tester, products: productsApi);
      await openStockTab(tester);

      expect(_avatarsWithPhoto, findsNothing);
      expect(find.text('S'), findsOneWidget);
    });
  });
}
