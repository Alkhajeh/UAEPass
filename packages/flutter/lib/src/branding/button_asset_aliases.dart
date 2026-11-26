// Byte-identical artwork families, documented in assets/button-artwork.json.
const buttonAssetAliases = <String, String>{
  'authorize/ar/fully_rounded_black_disabled':
      'authorize/ar/fully_rounded_white_outline_disabled',
  'authorize/ar/fully_rounded_black_pressed':
      'authorize/ar/fully_rounded_black_active',
  'authorize/ar/rounded_black_disabled':
      'authorize/ar/rounded_white_outline_disabled',
  'authorize/ar/rounded_black_pressed': 'authorize/ar/rounded_black_active',
  'authorize/ar/square_corners_black_disabled':
      'authorize/ar/square_corners_white_outline_disabled',
  'authorize/ar/square_corners_black_pressed':
      'authorize/ar/square_corners_black_active',
  'authorize/en/fully_rounded_black_disabled':
      'authorize/en/fully_rounded_white_outline_disabled',
  'authorize/en/fully_rounded_black_pressed':
      'authorize/en/fully_rounded_black_active',
  'authorize/en/rounded_black_disabled':
      'authorize/en/rounded_white_outline_disabled',
  'authorize/en/rounded_black_pressed': 'authorize/en/rounded_black_active',
  'authorize/en/square_corners_black_disabled':
      'authorize/en/square_corners_white_outline_disabled',
  'authorize/en/square_corners_black_pressed':
      'authorize/en/square_corners_black_active',
  'login/ar/fully_rounded_black_active':
      'sign_in/ar/fully_rounded_black_active',
  'login/ar/fully_rounded_black_disabled':
      'sign_in/ar/fully_rounded_black_disabled',
  'login/ar/fully_rounded_black_focused':
      'sign_in/ar/fully_rounded_black_focused',
  'login/ar/fully_rounded_black_pressed':
      'sign_in/ar/fully_rounded_black_active',
  'login/ar/fully_rounded_white_outline_disabled':
      'sign_in/ar/fully_rounded_black_disabled',
  'login/ar/rounded_black_active': 'sign_in/ar/rounded_black_active',
  'login/ar/rounded_black_disabled': 'sign_in/ar/rounded_black_disabled',
  'login/ar/rounded_black_focused': 'sign_in/ar/rounded_black_focused',
  'login/ar/rounded_black_pressed': 'sign_in/ar/rounded_black_active',
  'login/ar/rounded_white_outline_disabled':
      'sign_in/ar/rounded_black_disabled',
  'login/ar/square_corners_black_active':
      'sign_in/ar/square_corners_black_active',
  'login/ar/square_corners_black_disabled':
      'sign_in/ar/square_corners_black_disabled',
  'login/ar/square_corners_black_focused':
      'sign_in/ar/square_corners_black_focused',
  'login/ar/square_corners_black_pressed':
      'sign_in/ar/square_corners_black_active',
  'login/ar/square_corners_white_outline_disabled':
      'sign_in/ar/square_corners_black_disabled',
  'login/en/fully_rounded_black_disabled':
      'login/en/fully_rounded_white_outline_disabled',
  'login/en/fully_rounded_black_pressed': 'login/en/fully_rounded_black_active',
  'login/en/rounded_black_disabled': 'login/en/rounded_white_outline_disabled',
  'login/en/rounded_black_pressed': 'login/en/rounded_black_active',
  'login/en/square_corners_black_disabled':
      'login/en/square_corners_white_outline_disabled',
  'login/en/square_corners_black_pressed':
      'login/en/square_corners_black_active',
  'register_account/ar/fully_rounded_black_disabled':
      'register_account/ar/fully_rounded_white_outline_disabled',
  'register_account/ar/fully_rounded_black_pressed':
      'register_account/ar/fully_rounded_black_active',
  'register_account/ar/rounded_black_disabled':
      'register_account/ar/rounded_white_outline_disabled',
  'register_account/ar/rounded_black_pressed':
      'register_account/ar/rounded_black_active',
  'register_account/ar/square_corners_black_disabled':
      'register_account/ar/square_corners_white_outline_disabled',
  'register_account/ar/square_corners_black_pressed':
      'register_account/ar/square_corners_black_active',
  'register_account/en/fully_rounded_black_disabled':
      'register_account/en/fully_rounded_white_outline_disabled',
  'register_account/en/fully_rounded_black_pressed':
      'register_account/en/fully_rounded_black_active',
  'register_account/en/rounded_black_disabled':
      'register_account/en/rounded_white_outline_disabled',
  'register_account/en/rounded_black_pressed':
      'register_account/en/rounded_black_active',
  'register_account/en/square_corners_black_disabled':
      'register_account/en/square_corners_white_outline_disabled',
  'register_account/en/square_corners_black_pressed':
      'register_account/en/square_corners_black_active',
  'sign_in/ar/fully_rounded_black_pressed':
      'sign_in/ar/fully_rounded_black_active',
  'sign_in/ar/rounded_black_pressed': 'sign_in/ar/rounded_black_active',
  'sign_in/ar/square_corners_black_pressed':
      'sign_in/ar/square_corners_black_active',
  'sign_in/en/fully_rounded_black_disabled':
      'sign_in/en/fully_rounded_white_outline_disabled',
  'sign_in/en/fully_rounded_black_pressed':
      'sign_in/en/fully_rounded_black_active',
  'sign_in/en/rounded_black_disabled':
      'sign_in/en/rounded_white_outline_disabled',
  'sign_in/en/rounded_black_pressed': 'sign_in/en/rounded_black_active',
  'sign_in/en/square_corners_black_disabled':
      'sign_in/en/square_corners_white_outline_disabled',
  'sign_in/en/square_corners_black_pressed':
      'sign_in/en/square_corners_black_active',
  'sign_up/ar/fully_rounded_black_active':
      'register_account/ar/fully_rounded_black_active',
  'sign_up/ar/fully_rounded_black_disabled':
      'register_account/ar/fully_rounded_white_outline_disabled',
  'sign_up/ar/fully_rounded_black_focused':
      'register_account/ar/fully_rounded_black_focused',
  'sign_up/ar/fully_rounded_black_pressed':
      'register_account/ar/fully_rounded_black_active',
  'sign_up/ar/rounded_black_active': 'register_account/ar/rounded_black_active',
  'sign_up/ar/rounded_black_disabled':
      'register_account/ar/rounded_white_outline_disabled',
  'sign_up/ar/rounded_black_focused':
      'register_account/ar/rounded_black_focused',
  'sign_up/ar/rounded_black_pressed':
      'register_account/ar/rounded_black_active',
  'sign_up/ar/square_corners_black_active':
      'register_account/ar/square_corners_black_active',
  'sign_up/ar/square_corners_black_disabled':
      'register_account/ar/square_corners_white_outline_disabled',
  'sign_up/ar/square_corners_black_focused':
      'register_account/ar/square_corners_black_focused',
  'sign_up/ar/square_corners_black_pressed':
      'register_account/ar/square_corners_black_active',
  'sign_up/en/fully_rounded_black_disabled':
      'sign_up/en/fully_rounded_white_outline_disabled',
  'sign_up/en/fully_rounded_black_pressed':
      'sign_up/en/fully_rounded_black_active',
  'sign_up/en/rounded_black_disabled':
      'sign_up/en/rounded_white_outline_disabled',
  'sign_up/en/rounded_black_pressed': 'sign_up/en/rounded_black_active',
  'sign_up/en/square_corners_black_disabled':
      'sign_up/en/square_corners_white_outline_disabled',
  'sign_up/en/square_corners_black_pressed':
      'sign_up/en/square_corners_black_active',
  'sign/ar/fully_rounded_black_disabled':
      'sign/ar/fully_rounded_white_outline_disabled',
  'sign/ar/fully_rounded_black_pressed': 'sign/ar/fully_rounded_black_active',
  'sign/ar/rounded_black_disabled': 'sign/ar/rounded_white_outline_disabled',
  'sign/ar/rounded_black_pressed': 'sign/ar/rounded_black_active',
  'sign/ar/square_corners_black_disabled':
      'sign/ar/square_corners_white_outline_disabled',
  'sign/ar/square_corners_black_pressed': 'sign/ar/square_corners_black_active',
  'sign/en/fully_rounded_black_disabled':
      'sign/en/fully_rounded_white_outline_disabled',
  'sign/en/fully_rounded_black_pressed': 'sign/en/fully_rounded_black_active',
  'sign/en/rounded_black_disabled': 'sign/en/rounded_white_outline_disabled',
  'sign/en/rounded_black_pressed': 'sign/en/rounded_black_active',
  'sign/en/square_corners_black_disabled':
      'sign/en/square_corners_white_outline_disabled',
  'sign/en/square_corners_black_pressed': 'sign/en/square_corners_black_active',
};
