import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.bubabeautystudio.app',
  appName: 'Buba Beauty Studio',
  webDir: 'www',
  backgroundColor: '#FAF7F4',
  ios: {
    contentInset: 'always',
    scheme: 'BubaBeautyStudio',
    limitsNavigationsToAppBoundDomains: false,
  },
  server: {
    androidScheme: 'https',
    allowNavigation: [
      'bubabeautystudio.com',
      '*.bubabeautystudio.com',
      'booksy.com',
      '*.booksy.com',
      'instagram.com',
      '*.instagram.com',
      'wa.me',
      'api.whatsapp.com',
      'maps.apple.com',
    ],
  },
  plugins: {
    SplashScreen: {
      launchAutoHide: true,
      launchShowDuration: 1500,
      backgroundColor: '#FAF7F4',
      iosSpinnerStyle: 'small',
      showSpinner: false,
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#FAF7F4',
      overlaysWebView: false,
    },
  },
};

export default config;
