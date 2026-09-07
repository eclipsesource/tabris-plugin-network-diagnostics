class NetworkDiagnostics extends tabris.NativeObject {

  get _nativeType() {
    return 'com.eclipsesource.NetworkDiagnostics';
  }

  interfaces() {
    return this._promiseCall('interfaces', {});
  }

  _promiseCall(method, parameters) {
    return new Promise((resolve, reject) => {
      this._nativeCall(method, {
        parameters,
        completion: (error, result) => {
          if (error != null) {
            const rejection = new Error(error.message);
            rejection.code = error.code;
            reject(rejection);
          } else {
            resolve(result === undefined ? null : result);
          }
        }
      });
    });
  }

}

module.exports = NetworkDiagnostics;
