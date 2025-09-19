import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/theme/app_theme.dart';

class CityAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;
  final String? Function(String?)? validator;

  const CityAutocompleteField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.validator,
  });

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  List<Map<String, String>> _citySuggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Don't auto-detect location on init to prevent blocking UI
    // User can tap the location icon when they want to detect location
  }

  Future<void> _detectCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return;
      }

      // Check location permissions using geolocator
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return;
      }

      // Get current position with fallback to less accurate but faster location
      Position? position;
      try {
        // Try high accuracy first (faster on some devices)
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (e) {
        // If high accuracy fails, try low accuracy as fallback
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 3),
            ),
          );
        } catch (e2) {
          // If both fail, try getting last known position
          position = await Geolocator.getLastKnownPosition();
          if (position == null) {
            print('Could not get current or last known position');
            return;
          }
        }
      }

      // Get city from coordinates
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final city = placemark.locality ?? 
                     placemark.subAdministrativeArea ?? 
                     placemark.administrativeArea ?? '';
        
        if (city.isNotEmpty && widget.controller.text.isEmpty) {
          widget.controller.text = city;
        }
      }
    } catch (e) {
      print('Error detecting location: $e');
      // If location detection fails, just continue without auto-filling
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchCities(String query) async {
    if (query.length < 2) {
      setState(() {
        _citySuggestions = [];
        _showSuggestions = false;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Using OpenStreetMap Nominatim API for free worldwide city search
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?'
          'q=${Uri.encodeComponent(query)}&'
          'format=json&'
          'addressdetails=1&'
          'limit=5&'
          'featuretype=city&'
          'accept-language=en'
        ),
        headers: {
          'User-Agent': 'RatNawnAI/1.0',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        setState(() {
          _citySuggestions = data.map<Map<String, String>>((item) {
            // Extract city name and country for display
            final displayName = item['display_name']?.toString() ?? '';
            final addressDetails = item['address'] ?? {};
            
            String cityName = '';
            String country = addressDetails['country']?.toString() ?? '';
            
            // Try to get the best city name from different fields
            cityName = addressDetails['city']?.toString() ?? 
                       addressDetails['town']?.toString() ?? 
                       addressDetails['village']?.toString() ?? 
                       addressDetails['municipality']?.toString() ??
                       item['name']?.toString() ?? '';
                       
            // Create a clean display name
            String cleanDisplayName = cityName;
            if (country.isNotEmpty && cityName.isNotEmpty) {
              cleanDisplayName = '$cityName, $country';
            } else if (displayName.isNotEmpty) {
              // Extract the first part of display name as fallback
              final parts = displayName.split(',');
              cleanDisplayName = parts.isNotEmpty ? parts[0].trim() : displayName;
              if (country.isNotEmpty) {
                cleanDisplayName = '$cleanDisplayName, $country';
              }
            }
            
            return {
              'name': cityName.isNotEmpty ? cityName : cleanDisplayName.split(',')[0].trim(),
              'display': cleanDisplayName,
            };
          }).where((city) => city['name']!.isNotEmpty).toList();
          
          _showSuggestions = _citySuggestions.isNotEmpty;
          _isSearching = false;
        });
      } else {
        setState(() {
          _citySuggestions = [];
          _showSuggestions = false;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Error searching cities: $e');
      setState(() {
        _citySuggestions = [];
        _showSuggestions = false;
        _isSearching = false;
      });
    }
  }

  void _selectCity(Map<String, String> cityData) {
    widget.controller.text = cityData['name']!;
    setState(() {
      _showSuggestions = false;
      _citySuggestions = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // City input field
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.lightGrey,
              width: 1.5,
            ),
            color: AppColors.white,
          ),
          child: TextFormField(
            controller: widget.controller,
            validator: widget.validator,
            onChanged: (value) {
              // Debounce the search to avoid too many API calls
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && widget.controller.text == value) {
                  _searchCities(value);
                }
              });
            },
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              labelStyle: GoogleFonts.poppins(
                color: AppColors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              hintStyle: GoogleFonts.poppins(
                color: AppColors.lightGrey,
                fontSize: 14,
              ),
              prefixIcon: (_isLoading || _isSearching)
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                        ),
                      ),
                    )
                  : Icon(
                      widget.prefixIcon,
                      color: AppColors.grey,
                      size: 22,
                    ),
              suffixIcon: widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.grey),
                      onPressed: () {
                        widget.controller.clear();
                        setState(() {
                          _showSuggestions = false;
                          _citySuggestions = [];
                        });
                      },
                    )
                  : IconButton(
                      icon: const Icon(Icons.my_location, color: AppColors.primaryBlue),
                      onPressed: _isLoading ? null : _detectCurrentLocation,
                      tooltip: _isLoading ? 'Detecting location...' : 'Detect current location',
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
            ),
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: AppColors.darkGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        
        // City suggestions dropdown
        if (_showSuggestions && _citySuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.lightGrey),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _citySuggestions.length,
              itemBuilder: (context, index) {
                final cityData = _citySuggestions[index];
                return ListTile(
                  title: Text(
                    cityData['name']!,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: AppColors.darkGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: cityData['display'] != cityData['name'] 
                      ? Text(
                          cityData['display']!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  leading: const Icon(
                    Icons.public,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                  dense: true,
                  onTap: () => _selectCity(cityData),
                  hoverColor: AppColors.lightGrey.withOpacity(0.5),
                );
              },
            ),
          ),
        
        // Search status indicator
        if (_isSearching)
          Container(
            margin: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Searching cities worldwide...',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
